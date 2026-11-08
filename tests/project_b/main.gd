extends Node
## 起動すると Greeter (class_name) と、収録ルートシーンへの遷移を使う。
const BuildScenes := preload("res://{{ADDON}}/build_scenes.gd")

func _ready() -> void:
	print(Greeter.hello())
	var level := BuildScenes.load_root("res://levels/level_1.tscn")
	var node := level.instantiate()
	add_child(node)
	print("project_b: started ", node.name, " ", Settings.tile_name())
	get_tree().quit()
