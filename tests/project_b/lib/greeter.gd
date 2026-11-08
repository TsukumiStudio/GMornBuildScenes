class_name Greeter
extends RefCounted
## main.gd は class_name でしか参照しないので、この preload は class_name を辿らないと書き出しに入らない。
const GREETING := preload("res://lib/greeting.tres")

static func hello() -> String:
	return "project_b: " + GREETING.resource_name
