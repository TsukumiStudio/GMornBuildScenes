extends Node2D
## 型を持たない生のテキストは文字列でしか名指せない。読み込む行はプロファイルの例外にしてある。
const NOTES := "res://data/notes.txt"

func notes() -> String:
	return FileAccess.get_file_as_string(NOTES)
