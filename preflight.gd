extends SceneTree
## 書き出しの前の検査。書き出しと同じ閉包と検査を走らせ、失敗なら 1 で終わる。
##   godot --headless --path . --script res://addons/gmorn_build_scenes/preflight.gd -- --preset=<export_presets.cfg の name>
## 機能タグを直接渡すときは --features=a,b。
## --export-release=<出力先> (または --export-debug / --export-pack) を足すと、検査に通ったあと続けて書き出し、
## 書き出しの終了コードで終わる。出力先を省くと preset の export_path に書く。
## このとき閉包の外のスクリプトを preset の exclude_filter に一時的に足す。
## Godot 4.7 はスクリプトを EditorExportPlugin に渡さずに書き出すので、プラグインでは外せないため。
## export_presets.cfg は書き出しが終わったら元の内容に戻す。
const BuildClosure := preload("build_closure.gd")
const PRESETS := "res://export_presets.cfg"
## 書き出しの途中で止まったときに残る、元の export_presets.cfg。
const BACKUP := "res://export_presets.cfg.gmorn_build_scenes_backup"
const EXPORT_MODES: Array[String] = ["--export-release", "--export-debug", "--export-pack"]

func _initialize() -> void:
	var features := PackedStringArray()
	var preset := ""
	var export_mode := ""
	var export_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--features="):
			features = arg.trim_prefix("--features=").split(",", false)
		elif arg.begins_with("--preset="):
			preset = arg.trim_prefix("--preset=")
			features = _preset_features(preset)
		for mode: String in EXPORT_MODES:
			if arg == mode or arg.begins_with(mode + "="):
				export_mode = mode
				export_path = arg.trim_prefix(mode).trim_prefix("=")
	var result := BuildClosure.for_export(features)
	for message: String in result.errors:
		printerr("GMornBuildScenes: " + message)
	if not result.errors.is_empty():
		quit(1)
		return
	print("GMornBuildScenes preflight: %s %d ファイル" % [result.profile.resource_path if result.profile else "プロファイルなし", result.files.size()])
	if export_mode.is_empty():
		quit(0)
		return
	if preset.is_empty():
		printerr("GMornBuildScenes: 書き出すには --preset= で preset を指定する")
		quit(1)
		return
	quit(_export(preset, export_mode, export_path, _unused_scripts(result.files) if result.profile else PackedStringArray()))

## export_presets.cfg の exclude_filter に scripts を足して書き出し、元の内容に戻す。
func _export(preset: String, mode: String, path: String, scripts: PackedStringArray) -> int:
	if FileAccess.file_exists(BACKUP):
		printerr("GMornBuildScenes: %s が残っている。前の書き出しが途中で止まったので、中身を export_presets.cfg と見比べて戻してから消す" % BACKUP)
		return 1
	var original := FileAccess.get_file_as_string(PRESETS) # build_scenes: allow エディタの道具 (書き出し設定)
	var excluded := _with_excludes(original, preset, scripts)
	if excluded.is_empty():
		printerr("GMornBuildScenes: preset %s の exclude_filter を書き換えられない" % preset)
		return 1
	_write(BACKUP, original)
	_write(PRESETS, excluded)
	print("GMornBuildScenes: 閉包の外のスクリプト %d 本を外して書き出す" % scripts.size())
	var output: Array = []
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), mode, preset])
	if not path.is_empty():
		arguments.append(path)
	var code := OS.execute(OS.get_executable_path(), arguments, output, true)
	_write(PRESETS, original)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP))
	print("".join(output))
	return code

## プロジェクトのスクリプトのうち閉包に無いもの。.gdignore のフォルダーと隠しフォルダーは見ない。
func _unused_scripts(files: Dictionary, directory := "res://") -> PackedStringArray:
	var result := PackedStringArray()
	if BuildClosure.ignored(directory.path_join("_")):
		return result
	for name: String in DirAccess.get_directories_at(directory):
		if not name.begins_with("."):
			result.append_array(_unused_scripts(files, directory.path_join(name)))
	for name: String in DirAccess.get_files_at(directory):
		var path := directory.path_join(name)
		if name.get_extension() == "gd" and not files.has(path):
			result.append(path)
	return result

## preset の section の exclude_filter に scripts を足した export_presets.cfg の中身。見つからなければ空。
static func _with_excludes(text: String, preset: String, scripts: PackedStringArray) -> String:
	var lines := text.split("\n")
	var in_preset := false
	for index: int in lines.size():
		var line := lines[index]
		if line.begins_with("["):
			in_preset = false
		elif line == 'name="%s"' % preset:
			in_preset = true
		elif in_preset and line.begins_with("exclude_filter=\""):
			var current := line.trim_prefix("exclude_filter=\"").trim_suffix("\"")
			var filters := PackedStringArray([current]) if not current.is_empty() else PackedStringArray()
			filters.append_array(scripts)
			lines[index] = 'exclude_filter="%s"' % ",".join(filters)
			return "\n".join(lines)
	return ""

static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE) # build_scenes: allow エディタの道具 (書き出し設定)
	file.store_string(text)

func _preset_features(name: String) -> PackedStringArray:
	var presets := ConfigFile.new()
	if presets.load(PRESETS) != OK: # build_scenes: allow エディタの道具 (書き出し設定)
		printerr("GMornBuildScenes: %s を読めない" % PRESETS)
		return PackedStringArray()
	for section: String in presets.get_sections():
		if presets.get_value(section, "name", "") == name:
			return str(presets.get_value(section, "custom_features", "")).split(",", false)
	printerr("GMornBuildScenes: preset %s が無い" % name)
	return PackedStringArray()
