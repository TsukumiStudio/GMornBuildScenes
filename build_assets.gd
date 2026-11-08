extends RefCounted
## 実行中のシーンが型付きで持つ素材 (BuildDependencies) を、res:// パスを鍵に引く。ファイルは読まない。
## データ (JSON) に書いたパスは、素材の識別子としてだけ使う。持っていない素材を引くとエラーにして null を返し、
## 書き出しに入っていない素材を黙って読みに行かない。

## path → [Resource, 持っている BuildDependencies の数]
static var _held := {}
## エディタの道具 (シーン生成器など) だけが立てる。持っていない素材を path で読む。ゲームの実行時は立てない。
static var tool_loading := false

static func hold(resources: Array) -> void:
	for resource: Resource in resources:
		if resource == null or resource.resource_path.is_empty():
			continue
		var entry: Array = _held.get_or_add(resource.resource_path, [resource, 0])
		entry[1] += 1

static func release(resources: Array) -> void:
	for resource: Resource in resources:
		if resource == null or not _held.has(resource.resource_path):
			continue
		var entry: Array = _held[resource.resource_path]
		entry[1] -= 1
		if entry[1] <= 0:
			_held.erase(resource.resource_path)

static func has(path: String) -> bool:
	return _held.has(path) or (_tool() and ResourceLoader.exists(path))

static func find(path: String) -> Resource:
	if _held.has(path):
		return _held[path][0]
	if _tool() and ResourceLoader.exists(path):
		return load(path) # build_scenes: allow エディタの道具だけ
	push_error("GMornBuildScenes: %s を型付きで持つシーンが無い (BuildDependencies に入れる)" % path)
	return null

## JSON の中身。呼び出し側が書き換えても持っている素材は変わらないよう複製を返す。
static func json(path: String) -> Variant:
	var resource := find(path) as JSON
	if resource == null:
		return null
	var data: Variant = resource.data
	return data.duplicate(true) if data is Dictionary or data is Array else data

static func _tool() -> bool:
	return tool_loading or Engine.is_editor_hint()
