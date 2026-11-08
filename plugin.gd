@tool
extends EditorPlugin
const BuildScenes := preload("build_scenes.gd")
const ExportPlugin := preload("export_plugin.gd")
var _export: EditorExportPlugin

func _enter_tree() -> void:
	if not ProjectSettings.has_setting(BuildScenes.SETTING_PROFILES):
		ProjectSettings.set_setting(BuildScenes.SETTING_PROFILES, PackedStringArray())
	ProjectSettings.set_initial_value(BuildScenes.SETTING_PROFILES, PackedStringArray())
	ProjectSettings.add_property_info({"name": BuildScenes.SETTING_PROFILES, "type": TYPE_PACKED_STRING_ARRAY,
		"hint": PROPERTY_HINT_TYPE_STRING, "hint_string": "%d/%d:*.tres" % [TYPE_STRING, PROPERTY_HINT_FILE]})
	# 既定では「高度な設定」をオンにしないと見えないので、基本の一覧に出す。
	ProjectSettings.set_as_basic(BuildScenes.SETTING_PROFILES, true)
	_export = ExportPlugin.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	remove_export_plugin(_export)
