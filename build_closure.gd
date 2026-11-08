@tool
extends RefCounted
## ビルドプロファイルのルートシーンから、書き出しに入れるファイルを集めて検査する。
## エンジンの依存一覧 (get_dependencies) は .gd の preload を返さないので、スクリプトとシェーダーは本文を読んで辿る。
## 検査は行単位の字句の照合なので、変数に入れたパスの中身までは追えない。
const BuildScenes := preload("build_scenes.gd")
const BuildAssets := preload("build_assets.gd")
## res:// の文字列を検査するファイル。
const TEXT_EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "json", "gdshader", "gdshaderinc", "cfg", "csv", "txt"]
## パスで読み込む呼び出し。preload と、ConfigFile.load のようなインスタンスの load は当たらない。
const PATH_ACCESS := "(?<![\\w.])load\\(|ResourceLoader\\.(load|load_threaded_request)\\(|FileAccess\\.(open|get_file_as_string|get_file_as_bytes)\\(|DirAccess\\.(open|get_files_at|get_directories_at)\\("
## この印を含む行のパス読み込みは止めない: user:// の IO、型付きの参照から取ったパス、理由を書いた注記。
const PATH_ACCESS_OK: Array[String] = ["user://", ".resource_path", "# build_scenes: allow"]
## 書き出しに入れない設定。他のプロファイルは収録外のルートを名指すので、選ばれたプロファイルだけを入れる。
const IGNORED_SETTINGS: Array[String] = ["editor_plugins/enabled", BuildScenes.SETTING_PROFILES]

## 書き出すファイル (res:// のパス → true)。
var files := {}
## files のうち Resource でない生のファイル。Godot はこれを preset の include_filter に無ければ書き出さない。
var raw_files := {}
var errors: Array[String] = []
var _queue: Array[String] = []
var _checked := {}
## スクリプトのパス → 許す行の中身の集合。
var _exceptions := {}
var _used_exceptions := {}
var _class_paths := {}
var _class_regex: RegEx
var _res_regex := RegEx.create_from_string("res://[^\"'\\s\\\\)\\]]+")
var _preload_regex := RegEx.create_from_string("(?m)\\bpreload\\(\\s*\"([^\"\\n]+)\"\\s*\\)|^extends\\s+\"([^\"\\n]+)\"")
var _include_regex := RegEx.create_from_string("#include\\s+\"([^\"]+)\"")
var _access_regex := RegEx.create_from_string(PATH_ACCESS)

## 書き出しの機能タグからプロファイルを選んで検査する。プロファイルが1つも無いプロジェクトでは何もしない。
## プロファイルがあるのに、どれにも当たらない・複数に当たる・設定のファイルが無いときは、全部入りにせず失敗にする。
static func for_export(features: PackedStringArray) -> Dictionary:
	var result := {"profile": null, "files": {}, "raw_files": {}, "errors": []}
	var paths := BuildScenes.profile_paths()
	if paths.is_empty():
		return result
	for path: String in paths:
		if not ResourceLoader.exists(path):
			result.errors.append("%s の %s が見つからない" % [BuildScenes.SETTING_PROFILES, path])
	var matched := BuildScenes.matching(features)
	if matched.size() != 1:
		var names := ", ".join(PackedStringArray(matched.map(func(profile: Resource) -> String: return profile.resource_path)))
		result.errors.append("機能タグ %s に当たるプロファイルが %s" % [features, "無い" if matched.is_empty() else "複数ある: " + names])
	if not result.errors.is_empty():
		return result
	var closure := preload("build_closure.gd").new().build(matched[0])
	return {"profile": matched[0], "files": closure.files, "raw_files": closure.raw_files, "errors": closure.errors}

## .gdignore のあるフォルダー (とその下) のファイル。Godot はプロジェクトの素材として扱わず、書き出さない。
static func ignored(path: String) -> bool:
	var directory := path.get_base_dir()
	while directory.begins_with("res://") and directory != "res://":
		if FileAccess.file_exists(directory.path_join(".gdignore")):
			return true
		directory = directory.get_base_dir()
	return false

func build(profile: Resource) -> RefCounted:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_class_paths[str(entry["class"])] = str(entry.path)
	if not _class_paths.is_empty():
		_class_regex = RegEx.create_from_string("\\b(" + "|".join(PackedStringArray(_class_paths.keys())) + ")\\b")
	for exception: Resource in profile.path_access_exceptions:
		_exceptions.get_or_add(BuildScenes.normalize(exception.script_path), {})[str(exception.code).strip_edges()] = true
	if not profile.resource_path.is_empty():
		_add(profile.resource_path, "プロファイル")
	var roots := BuildScenes.root_scenes(profile)
	if roots.is_empty():
		errors.append("%s: root_scenes が空" % profile.resource_path)
	for root: String in roots:
		if ResourceLoader.exists(root, "PackedScene"):
			_add(root, profile.resource_path)
		else:
			errors.append("%s: ルートシーン %s が見つからない" % [profile.resource_path, root])
	for path: String in _project_roots():
		# 既定値のまま使われていない設定 (default_bus_layout.tres など) は名前だけで、ファイルが無い。
		if FileAccess.file_exists(path) or ResourceLoader.exists(path):
			_add(path, "project.godot")
	# 検査で生のファイル (csv など) が見つかると閉包が増えるので、増えなくなるまで辿り直す。
	while true:
		while not _queue.is_empty():
			_visit(_queue.pop_back())
		var pending: Array = files.keys().filter(func(path: String) -> bool: return not _checked.has(path))
		if pending.is_empty():
			break
		for path: String in pending:
			_checked[path] = true
			_check_text(path)
	for script: String in _exceptions:
		for code: String in _exceptions[script]:
			if files.has(script) and not _used_exceptions.has(script + "\n" + code):
				errors.append("%s: 例外にした行が見つからない (行が変わったら例外を見直す): %s" % [script, code])
	return self

## main scene・autoload・テーマなど、プロジェクト設定が名指すもの。
func _project_roots() -> PackedStringArray:
	# 実行時に使うこのアドオンのスクリプト。アドオンを置くフォルダーはどこでもよい。
	var result := PackedStringArray([_script_path(BuildScenes), _script_path(BuildAssets)])
	for property: Dictionary in ProjectSettings.get_property_list():
		var name := str(property.name)
		if name in IGNORED_SETTINGS or not ProjectSettings.has_setting(name):
			continue
		var value: Variant = ProjectSettings.get_setting(name)
		var values: Array = value if value is Array or value is PackedStringArray else [value]
		for item: Variant in values:
			var text := str(item).trim_prefix("*")
			if text.begins_with("res://") or text.begins_with("uid://"):
				result.append(BuildScenes.normalize(text))
	return result

func _add(path: String, from: String) -> void:
	path = BuildScenes.normalize(path)
	if files.has(path) or DirAccess.dir_exists_absolute(path):
		return
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		errors.append("%s が参照する %s が見つからない" % [from, path])
		return
	if ignored(path):
		errors.append("%s が参照する %s は .gdignore のあるフォルダーにあり、書き出されない" % [from, path])
		return
	files[path] = true
	_queue.append(path)

func _visit(path: String) -> void:
	for dependency: String in ResourceLoader.get_dependencies(path):
		_add(dependency.get_slice("::", dependency.get_slice_count("::") - 1), path)
	var extension := path.get_extension()
	if extension not in ["gd", "gdshader", "gdshaderinc"]:
		return
	var text := FileAccess.get_file_as_string(path)
	var regex := _preload_regex if extension == "gd" else _include_regex
	for match: RegExMatch in regex.search_all(text):
		var target := match.get_string(1) if not match.get_string(1).is_empty() else match.get_string(2)
		if not target.begins_with("res://") and not target.begins_with("uid://"):
			target = path.get_base_dir().path_join(target).simplify_path()
		_add(target, path)
	if extension == "gd" and _class_regex != null:
		for match: RegExMatch in _class_regex.search_all(text):
			if _class_paths[match.get_string(1)] != path:
				_add(_class_paths[match.get_string(1)], path)

## 文字列の res:// が書き出しに入らない素材を指す行と、パスで読み込む行を止める。
func _check_text(path: String) -> void:
	if path.get_extension() not in TEXT_EXTENSIONS:
		return
	var is_script := path.get_extension() == "gd"
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for index: int in lines.size():
		var line := lines[index]
		# シーン・リソースの ext_resource は型付きの参照で、依存として辿り済み。
		if line.begins_with("[ext_resource"):
			continue
		var where := "%s:%d" % [path, index + 1]
		for match: RegExMatch in _res_regex.search_all(line):
			_check_string(BuildScenes.normalize(match.get_string()), where)
		var code := line.strip_edges()
		if is_script and not code.begins_with("#") and _access_regex.search(line) != null \
				and not PATH_ACCESS_OK.any(func(token: String) -> bool: return token in line) \
				and not _excepted(path, code):
			errors.append("%s: パスで読み込んでいる。型付きの参照で持たせて build_assets.gd で引くか、例外にする: %s" % [where, code])

func _excepted(path: String, code: String) -> bool:
	if not _exceptions.get(path, {}).has(code):
		return false
	_used_exceptions[path + "\n" + code] = true
	return true

func _check_string(target: String, where: String) -> void:
	if files.has(target) or DirAccess.dir_exists_absolute(target):
		return
	# 書式文字列や元データの記録にあるだけの名前は、全部入りの書き出しにも無いので見ない。
	if (not FileAccess.file_exists(target) and not ResourceLoader.exists(target)) or ignored(target):
		return
	# 型を持たない生のファイル (csv・txt など) は文字列でしか名指せないので、名指せば入れる。
	if _is_raw(target):
		raw_files[target] = true
		_add(target, where)
		return
	errors.append("%s: %s を文字列でしか名指していないので書き出しに入らない。シーンの外部参照・preload・@export・BuildDependencies で持たせる" % [where, target])

## Resource として読めないファイル。importer="keep" の csv も含む。
func _is_raw(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return true
	var import_path := path + ".import"
	return FileAccess.file_exists(import_path) and 'importer="keep"' in FileAccess.get_file_as_string(import_path)

## preload した Script の resource_path は、型付きの変数を通さないと読めない。
static func _script_path(script: Script) -> String:
	return script.resource_path
