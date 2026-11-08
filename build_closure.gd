@tool
extends RefCounted
## ビルドプロファイルのルートから、書き出しに入れるファイルの閉包を作り、パスに頼る参照を検査する。
## 辿るもの: ResourceLoader.get_dependencies (シーン・リソースの外部参照)、スクリプトの preload・extends・
## class_name の利用、シェーダーの #include。エンジンは .gd の preload を依存として返さないので自前で読む。
## 任意の GDScript を完全には解析できない。検査は行単位の字句の照合で、計算したパスの中身までは追えない。
const BuildScenes := preload("build_scenes.gd")
const BuildAssets := preload("build_assets.gd")
const TEXT_EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "json", "gdshader", "gdshaderinc", "cfg", "csv", "txt"]
## パスで読み込む呼び出し。preload と、ConfigFile.load などのインスタンスの load は当たらない。
const PATH_ACCESS := "(?<![\\w.])load\\(|ResourceLoader\\.(load|load_threaded_request)\\(|FileAccess\\.(open|get_file_as_string|get_file_as_bytes)\\(|DirAccess\\.(open|get_files_at|get_directories_at)\\("
## この行のパスは res:// の素材ではない、または型付きの参照から取ったもの。
const PATH_ACCESS_OK: Array[String] = ["user://", ".resource_path", "# build_scenes: allow"]
## 書き出しに入れない設定。他の profile は収録外のルートを名指すので、選ばれた profile だけを入れる。
const IGNORED_SETTINGS: Array[String] = ["editor_plugins/enabled", BuildScenes.SETTING_PROFILES]

## 書き出すファイル (res:// の path → true)。
var files := {}
var errors: Array[String] = []
var _queue: Array[String] = []
var _checked := {}
## script → 許す行の中身の集合 (path_access_exception.gd)。
var _exceptions := {}
var _used_exceptions := {}
var _class_paths := {}
var _class_regex: RegEx
var _res_regex := RegEx.create_from_string("res://[^\"'\\s\\\\)\\]]+")
var _preload_regex := RegEx.create_from_string("(?m)\\bpreload\\(\\s*\"([^\"\\n]+)\"\\s*\\)|^extends\\s+\"([^\"\\n]+)\"")
var _include_regex := RegEx.create_from_string("#include\\s+\"([^\"]+)\"")
var _access_regex := RegEx.create_from_string(PATH_ACCESS)

func build(profile: Resource) -> RefCounted:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_class_paths[str(entry["class"])] = str(entry.path)
	if not _class_paths.is_empty():
		_class_regex = RegEx.create_from_string("\\b(" + "|".join(PackedStringArray(_class_paths.keys())) + ")\\b")
	if not profile.resource_path.is_empty():
		_add(profile.resource_path, "profile")
	var roots := BuildScenes.root_scenes(profile)
	if roots.is_empty():
		errors.append("%s: root_scenes が空" % profile.resource_path)
	for root: String in roots:
		if not ResourceLoader.exists(root, "PackedScene"):
			errors.append("%s: ルートシーン %s が無い" % [profile.resource_path, root])
		_add(root, profile.resource_path)
	for path: String in _project_roots():
		# 既定値のまま使われていない設定 (default_bus_layout.tres など) は名前だけで、ファイルが無い。
		if FileAccess.file_exists(path) or ResourceLoader.exists(path):
			_add(path, "project.godot")
	for exception: Resource in profile.path_access_exceptions:
		_exceptions.get_or_add(BuildScenes.normalize(exception.script_path), {})[str(exception.code).strip_edges()] = true
	while true:
		while not _queue.is_empty():
			_visit(_queue.pop_back())
		var pending: Array = files.keys().filter(func(path: String) -> bool: return not _checked.has(path))
		if pending.is_empty():
			break
		for path: String in pending:
			_checked[path] = true
			_check_text(path, profile)
	for script: String in _exceptions:
		for code: String in _exceptions[script]:
			if files.has(script) and not _used_exceptions.has(script + "\n" + code):
				errors.append("%s: 例外の行が見つからない (行が変わったら例外を見直す): %s" % [script, code])
	return self

## 書き出しの機能タグから profile を選んで検査する。profile が1つも無いプロジェクトは何もしない (profile は null)。
## profile があるのにどれにも当たらない書き出しは、黙って全部入りにせずエラーにする。
static func for_export(features: PackedStringArray) -> Dictionary:
	if BuildScenes.profiles().is_empty():
		return {"profile": null, "files": {}, "errors": []}
	var profile := BuildScenes.for_features(features)
	if profile == null:
		return {"profile": null, "files": {}, "errors": ["機能タグ %s に当たるビルドプロファイルが無い (%s)" % [features, BuildScenes.SETTING_PROFILES]]}
	var own_path := _script_path(BuildScenes).get_base_dir().path_join("build_closure.gd")
	var closure = load(own_path).new().build(profile) # build_scenes: allow 自分自身
	return {"profile": profile, "files": closure.files, "errors": closure.errors}

func _project_roots() -> PackedStringArray:
	# 実行時に使うこのアドオンのスクリプト。置き場はどこでもよい。
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
		errors.append("%s が参照する %s が無い" % [from, path])
		return
	if ignored(path):
		errors.append("%s が参照する %s は .gdignore の置き場にあり、書き出しに入らない" % [from, path])
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

## 文字列の res:// が書き出しに入らない素材を指していたら止める。パスで読み込むコードは許した glob の外なら止める。
func _check_text(path: String, _profile: Resource) -> void:
	if path.get_extension() not in TEXT_EXTENSIONS:
		return
	var is_script := path.get_extension() == "gd"
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for index: int in lines.size():
		var line := lines[index]
		# シーン・リソースの ext_resource は型付きの参照で、依存として辿り済み。
		if line.begins_with("[ext_resource"):
			continue
		for match: RegExMatch in _res_regex.search_all(line):
			_check_string(BuildScenes.normalize(match.get_string()), "%s:%d" % [path, index + 1])
		var code := line.strip_edges()
		if is_script and not code.begins_with("#") and _access_regex.search(line) != null \
				and not PATH_ACCESS_OK.any(func(token: String) -> bool: return token in line) \
				and not _excepted(path, code):
			errors.append("%s:%d: パスでの読み込み。型付きの参照 (preload・@export・BuildDependencies) にして build_assets.gd で引く: %s" % [path, index + 1, code])

func _excepted(path: String, code: String) -> bool:
	if not _exceptions.get(path, {}).has(code):
		return false
	_used_exceptions[path + "\n" + code] = true
	return true

func _check_string(target: String, where: String) -> void:
	if files.has(target) or DirAccess.dir_exists_absolute(target):
		return
	if (not FileAccess.file_exists(target) and not ResourceLoader.exists(target)) or ignored(target):
		return # 書式文字列や、元データの記録にあるだけの名前。全部入りの書き出しにも無い。
	if _is_raw(target):
		_add(target, where) # 型を持たない生のファイル (csv・txt など) は文字列でしか名指せない。
		return
	errors.append("%s: %s は文字列で名指されているが、型付きの参照が無いので書き出しに入らない" % [where, target])

## .gdignore のある置き場 (とその下) のファイル。Godot はプロジェクトの素材として扱わず、書き出さない。
static func ignored(path: String) -> bool:
	var directory := path.get_base_dir()
	while directory.begins_with("res://") and directory != "res://":
		if FileAccess.file_exists(directory.path_join(".gdignore")):
			return true
		directory = directory.get_base_dir()
	return false

## Resource として読めないファイル。importer="keep" の csv なども含む。
func _is_raw(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return true
	var import_path := path + ".import"
	return FileAccess.file_exists(import_path) and 'importer="keep"' in FileAccess.get_file_as_string(import_path)

static func _script_path(script: Script) -> String:
	return script.resource_path
