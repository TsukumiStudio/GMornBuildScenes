@tool
extends Node
## 画面に出さないが実行時に使う素材を、型付きの参照としてシーンに持たせる。
## 書き出しはこの参照を依存として辿る。実行時は build_assets.gd がこの素材を path で引く。
const BuildAssets := preload("build_assets.gd")

@export var resources: Array[Resource] = []:
	set(value):
		BuildAssets.release(resources)
		resources = value
		BuildAssets.hold(resources)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		BuildAssets.release(resources)
