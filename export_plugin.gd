@tool
extends EditorExportPlugin
## 機能タグが profile に当たる書き出しだけ、閉包の外のファイルを外す。
## 検査に失敗したら、エラーを出して何も入れず、書き出した成果物を消す。
## EditorExportPlugin には書き出しを失敗 (非0終了) にする API が無い。非0終了で止めるのは preflight.gd の役目で、
## CI は書き出しの前に preflight を走らせる。ここは preflight を通らずに書き出したときの保険。
const BuildClosure := preload("build_closure.gd")
var _files := {}
var _active := false
var _failed := false
var _path := ""

func _get_name() -> String:
	return "GMornBuildScenes"

func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_path = path
	var result := BuildClosure.for_export(features)
	_active = result.profile != null
	_files = result.files
	_failed = not result.errors.is_empty()
	for message: String in result.errors:
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "GMornBuildScenes", message)
		printerr("GMornBuildScenes: " + message)
	if _active and not _failed:
		print("GMornBuildScenes: %s で %d ファイルを書き出す" % [result.profile.resource_path, _files.size()])

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _failed or (_active and not _files.has(path)):
		skip()

func _export_end() -> void:
	if not _failed:
		return
	# 使えない成果物を残さない。pck だけの書き出しは path そのもの、それ以外は横の .pck が中身。
	for target: String in [_path, _path.get_basename() + ".pck"]:
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
	printerr("GMornBuildScenes: 検査に失敗したので %s を消した。preflight.gd で理由を確かめる" % _path)
