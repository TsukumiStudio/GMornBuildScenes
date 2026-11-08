extends RefCounted
## 実行時と書き出しで共通: どのビルドプロファイルが有効か、どのルートシーンが収録されているか。
const SETTING_PROFILES := "gmorn_build_scenes/profiles"

## project settings の gmorn_build_scenes/profiles に並べた profile。
static func profiles() -> Array[Resource]:
	var result: Array[Resource] = []
	if not ProjectSettings.has_setting(SETTING_PROFILES):
		return result
	for path: String in ProjectSettings.get_setting(SETTING_PROFILES):
		# 書き出しには選ばれた profile だけが入る。
		if not ResourceLoader.exists(path):
			continue
		var profile := load(path) as Resource # build_scenes: allow profile の一覧は project settings が持つ
		if profile == null:
			push_error("GMornBuildScenes: profile が読めない: " + path)
			continue
		result.append(profile)
	return result

## features のどれかを feature に持つ profile。無ければ null (全部入りの通常の書き出し)。
static func for_features(features: PackedStringArray) -> Resource:
	var found: Resource = null
	for profile: Resource in profiles():
		if not str(profile.feature).is_empty() and features.has(profile.feature):
			if found != null:
				push_error("GMornBuildScenes: 機能タグが2つの profile に当たる: %s, %s" % [found.resource_path, profile.resource_path])
			found = profile
	return found

## 実行中の書き出しの profile。Editor から実行したときは null。
static func active() -> Resource:
	for profile: Resource in profiles():
		if not str(profile.feature).is_empty() and OS.has_feature(profile.feature):
			return profile
	return null

## uid:// を res:// にそろえる。
static func normalize(path: String) -> String:
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else path
	return path

static func root_scenes(profile: Resource) -> PackedStringArray:
	var result := PackedStringArray()
	for path: String in profile.root_scenes:
		result.append(normalize(path))
	return result

## profile が null (全部入り) なら常に true。
static func has_root(path: String, profile: Resource = active()) -> bool:
	return profile == null or root_scenes(profile).has(normalize(path))

## 収録されたルートシーンへの遷移。収録外は null を返して理由を出す。
static func load_root(path: String, profile: Resource = active()) -> PackedScene:
	if not has_root(path, profile):
		push_error("GMornBuildScenes: %s はこの書き出し (%s) に収録されていない" % [path, profile.feature])
		return null
	return load(path) as PackedScene # build_scenes: allow 収録ルートシーンへの遷移
