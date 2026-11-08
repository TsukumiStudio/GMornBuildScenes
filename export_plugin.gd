@tool
extends EditorExportPlugin
## プロファイルに当たる書き出しで、閉包の外のファイルを外し、閉包の中の生のファイルを足す。
## 検査に失敗したら、エラーを出して何も入れず、最後に成果物を消す。
## EditorExportPlugin には書き出しを失敗 (非0終了) にする API が無い。非0終了で止めるのは preflight.gd の役目。
const BuildClosure := preload("build_closure.gd")
var _files := {}
var _raw_files := {}
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
	_raw_files = result.raw_files
	_failed = not result.errors.is_empty()
	for message: String in result.errors:
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "GMornBuildScenes", message)
		printerr("GMornBuildScenes: " + message)
	if not _active or _failed:
		return
	# 生のファイルはここで足し、preset の include_filter で入る同じファイルは _export_file で外す (二重に入れない)。
	for raw: String in _raw_files:
		add_file(raw, FileAccess.get_file_as_bytes(raw), false) # build_scenes: allow 閉包が名指した生のファイル
	print("GMornBuildScenes: %s で %d ファイルを書き出す" % [result.profile.resource_path, _files.size()])

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _failed or (_active and (not _files.has(path) or _raw_files.has(path))):
		skip()

func _export_end() -> void:
	if not _failed:
		return
	# 使えない成果物を残さない。pck だけの書き出しは path そのもの、それ以外は横の .pck が中身。
	for target: String in [_path, _path.get_basename() + ".pck"]:
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
	printerr("GMornBuildScenes: 検査に失敗したので %s を消した。preflight.gd で理由を確かめる" % _path)
