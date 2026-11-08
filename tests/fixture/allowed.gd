extends RefCounted

func read(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func write(path: String) -> void:
	FileAccess.open(path, FileAccess.WRITE)
