extends RefCounted
## 実行時と書き出しで共通: どのビルドプロファイルが有効か、どのルートシーンが収録されているか。
const SETTING_PROFILES := "gmorn_build_scenes/profiles"

## プロジェクト設定 gmorn_build_scenes/profiles に並べたパス。
static func profile_paths() -> PackedStringArray:
	return ProjectSettings.get_setting(SETTING_PROFILES, PackedStringArray())

## 読めるプロファイル。書き出しには選ばれたプロファイルだけが入るので、無いファイルは飛ばす。
static func profiles() -> Array[Resource]:
	var result: Array[Resource] = []
	for path: String in profile_paths():
		if ResourceLoader.exists(path):
			result.append(load(path)) # build_scenes: allow プロファイルの一覧はプロジェクト設定が持つ
	return result

## 機能タグのどれかを feature に持つプロファイル。
static func matching(features: PackedStringArray) -> Array[Resource]:
	var result: Array[Resource] = []
	for profile: Resource in profiles():
		if not str(profile.feature).is_empty() and features.has(profile.feature):
			result.append(profile)
	return result

## 機能タグにちょうど1つ当たるプロファイル。当たらないか複数なら null。
static func for_features(features: PackedStringArray) -> Resource:
	var found := matching(features)
	return found[0] if found.size() == 1 else null

## 実行中の書き出しのプロファイル。Editor から実行したときは null (全部入り)。
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

## プロファイルが null (全部入り) なら常に true。
static func has_root(path: String, profile: Resource = active()) -> bool:
	return profile == null or root_scenes(profile).has(normalize(path))

## 収録されたルートシーンへの遷移。収録外は null を返して理由を出す。
static func load_root(path: String, profile: Resource = active()) -> PackedScene:
	if not has_root(path, profile):
		push_error("GMornBuildScenes: %s はこの書き出し (%s) に収録されていない" % [path, profile.feature])
		return null
	return load(path) as PackedScene # build_scenes: allow 収録ルートシーンへの遷移
