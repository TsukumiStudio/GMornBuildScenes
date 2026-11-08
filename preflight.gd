extends SceneTree
## 書き出しの前の検査。書き出しと同じ閉包と検査を走らせ、失敗なら 1 で終わる。
## godot --headless --path . --script res://addons/gmorn_build_scenes/preflight.gd -- --preset=<export_presets.cfg の name>
## 機能タグを直接渡すときは --features=a,b。
const BuildClosure := preload("build_closure.gd")
const PRESETS := "res://export_presets.cfg"

func _initialize() -> void:
	var features := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--features="):
			features = arg.trim_prefix("--features=").split(",", false)
		elif arg.begins_with("--preset="):
			features = _preset_features(arg.trim_prefix("--preset="))
	var result := BuildClosure.for_export(features)
	for message: String in result.errors:
		printerr("GMornBuildScenes: " + message)
	if result.errors.is_empty():
		print("GMornBuildScenes preflight: %s %d ファイル" % [result.profile.resource_path if result.profile else "profile なし", result.files.size()])
	quit(0 if result.errors.is_empty() else 1)

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
