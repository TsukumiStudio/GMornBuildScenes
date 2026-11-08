@tool
extends Resource
## 1つの書き出しに入れるもの (Unity の Build Settings の Scenes In Build)。
## 書き出し preset の機能タグに feature があるとき、このプロファイルが選ばれる。

## 書き出し preset の custom_features に足す機能タグ。
@export var feature := ""
## 収録するルートシーン。外部参照・preload・型付きの @export で辿れるものが一緒に入る。
@export_file("*.tscn", "*.scn") var root_scenes: Array[String] = []
## パスで読み込む行の例外 (path_access_exception.gd)。user:// の IO など、型付きの参照にできないものだけ。
@export var path_access_exceptions: Array[Resource] = []
