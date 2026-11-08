extends Node
## 検査を通るルート。型付きの参照だけで素材を持ち、実行時は build_assets.gd で引く。
const Helper := preload("helper.gd")
const BuildAssets := preload("../../build_assets.gd")

func _ready() -> void:
	print(BuildAssets.json("res://addons/gmorn_build_scenes/tests/fixture/clean.json"))
