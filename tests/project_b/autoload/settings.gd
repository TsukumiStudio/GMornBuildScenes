extends Node
const TILE := preload("res://shared/tile.tres")

func tile_name() -> String:
	return TILE.resource_name
