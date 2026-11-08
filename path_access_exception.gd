@tool
extends Resource
## パスで読み込む1行を許す。外部のアドオンの user:// の IO など、型付きの参照にできない正当なものだけ。
## script_path と code (前後の空白を除いた行の中身) が両方一致する行だけを許す。行が変わればまた止まる。
@export_file("*.gd") var script_path := ""
@export var code := ""
@export_multiline var reason := ""
