extends Node
const Helper := preload("helper.gd")
const Cycle := preload("cycle_a.gd")

func _ready() -> void:
	var path := "res://addons/gmorn_build_scenes/tests/fixture/dynamic.tres"
	print(load(path))
	print(load("res://addons/gmorn_build_scenes/tests/fixture/annotated.tres")) # build_scenes: allow 検査の例
	print(FileAccess.open("user://save.json", FileAccess.READ))
