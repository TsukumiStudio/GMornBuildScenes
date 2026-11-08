extends SceneTree
## 閉包・検査・実行時の取得の単体テスト。verify.sh が合成プロジェクト A に写して回す (preflight と書き出しは verify.sh が見る)。
## 閉包: 型付きの参照の連鎖 (再帰)、互いに preload するスクリプト (循環)、2つのルートが共有する素材を1度だけ入れる。
## 検査: 型付きの参照の無い文字列パス・許していないパス読み込み・無いルート・使われていない例外を止める。
const BuildProfile = preload("res://addons/gmorn_build_scenes/build_profile.gd")
const PathAccessException = preload("res://addons/gmorn_build_scenes/path_access_exception.gd")
const BuildClosure = preload("res://addons/gmorn_build_scenes/build_closure.gd")
const BuildAssets = preload("res://addons/gmorn_build_scenes/build_assets.gd")
const DIR := "res://addons/gmorn_build_scenes/tests/fixture/"
var failures: Array[String] = []

func _initialize() -> void:
	_test_closure_follows_typed_references_cycles_and_shared()
	_test_checks_stop_untyped_paths_and_path_access()
	_test_line_exceptions_are_exact_and_must_be_used()
	_test_runtime_lookup_only_finds_held_resources()
	print("BUILD_SCENES TEST: PASS" if failures.is_empty() else "TEST_BUILD_SCENES FAIL %d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_closure_follows_typed_references_cycles_and_shared() -> void:
	var closure := BuildClosure.new().build(_profile(["root.tscn", "other.tscn"], []))
	for name: String in ["root.tscn", "other.tscn", "root.gd", "helper.gd", "cycle_a.gd", "cycle_b.gd", "data.json",
			"typed.tres", "allowed.gd", "chain_a.tres", "chain_b.tres", "shared.tres"]:
		_check(closure.files.has(DIR + name), "閉包に %s が無い" % name)
	for name: String in ["untyped.tres", "dynamic.tres", "annotated.tres"]:
		_check(not closure.files.has(DIR + name), "型付きの参照の無い %s が閉包に入った" % name)

func _test_checks_stop_untyped_paths_and_path_access() -> void:
	var errors := _fixture_errors(BuildClosure.new().build(_profile(["root.tscn"], [])))
	_check(_has(errors, "data.json:1: " + DIR + "untyped.tres を文字列でしか名指していない"), "JSON の文字列だけの参照を止めない")
	_check(_has(errors, "root.gd:6: " + DIR + "dynamic.tres を文字列でしか名指していない"), "スクリプトに書いた res:// を止めない")
	_check(_has(errors, "root.gd:7: パスで読み込んでいる"), "変数パスの load を止めない")
	_check(not _has(errors, "root.gd:8: パスで読み込んでいる"), "理由を書いた注記の行を止めた")
	_check(_has(errors, "root.gd:8: " + DIR + "annotated.tres を文字列でしか名指していない"), "注記しても書き出しに入らない素材を止めない")
	_check(not _has(errors, "root.gd:9"), "user:// の読み込みを止めた")
	_check(_has(errors, "allowed.gd:4: パスで読み込んでいる") and _has(errors, "allowed.gd:7: パスで読み込んでいる"), "例外の無いスクリプトのパス読み込みを止めない")
	_check(not _has(errors, "never_existed"), "どこにも無いファイル名 (元データの記録) を止めた")
	_check(not _has(errors, "ignored/record.json"), ".gdignore のフォルダーを名指す文字列 (元データの記録) を止めた")
	var closure := BuildClosure.new()
	closure._add(DIR + "ignored/record.json", "検査")
	_check(_has(closure.errors, "ignored/record.json は .gdignore のあるフォルダーにあり"), ".gdignore のフォルダーへの型付きの参照を止めない")
	var missing := BuildClosure.new().build(_profile(["missing.tscn"], []))
	_check(_has(missing.errors, "ルートシーン " + DIR + "missing.tscn が見つからない"), "無いルートシーンを止めない")

## 例外は script と行の中身の両方が一致する行だけを許す。同じスクリプトの別の行や、見つからない例外は止める。
func _test_line_exceptions_are_exact_and_must_be_used() -> void:
	var read := _exception("allowed.gd", "return FileAccess.get_file_as_string(path)")
	var errors := _fixture_errors(BuildClosure.new().build(_profile(["root.tscn"], [read])))
	_check(not _has(errors, "allowed.gd:4"), "例外にした行を止めた")
	_check(_has(errors, "allowed.gd:7: パスで読み込んでいる"), "例外にしていない同じスクリプトの行を許した")
	var stale := _exception("allowed.gd", "return load(path)")
	var stale_errors := _fixture_errors(BuildClosure.new().build(_profile(["root.tscn"], [stale])))
	_check(_has(stale_errors, "allowed.gd: 例外にした行が見つからない"), "使われていない例外を止めない")

func _test_runtime_lookup_only_finds_held_resources() -> void:
	var path := DIR + "data.json"
	_check(not BuildAssets.has(path), "持つ前から引けた")
	var scene: Node = load(DIR + "root.tscn").instantiate()
	_check(BuildAssets.has(path) and BuildAssets.json(path) == {"typed": DIR + "typed.tres", "untyped": DIR + "untyped.tres", "provenance": DIR + "never_existed.prefab", "receipt": DIR + "ignored/record.json"}, "シーンが持つ JSON を引けない")
	var copy: Dictionary = BuildAssets.json(path)
	copy.typed = "changed"
	_check(BuildAssets.json(path).typed == DIR + "typed.tres", "引いた JSON を書き換えると持っている素材が変わる")
	_check(BuildAssets.find(DIR + "chain_a.tres") != null, "シーンが持つ素材を引けない")
	_check(not BuildAssets.has(DIR + "untyped.tres"), "持っていない素材を引けた")
	var second: Node = load(DIR + "root.tscn").instantiate()
	scene.free()
	_check(BuildAssets.has(path), "同じ素材を持つ別のシーンが残っているのに引けなくなった")
	second.free()
	_check(not BuildAssets.has(path), "シーンを消しても引ける")

func _profile(roots: Array, exceptions: Array) -> Resource:
	var profile: Resource = BuildProfile.new()
	profile.root_scenes.assign(roots.map(func(name: String) -> String: return DIR + name))
	profile.path_access_exceptions.assign(exceptions)
	return profile

func _exception(script: String, code: String) -> Resource:
	var exception: Resource = PathAccessException.new()
	exception.script_path = DIR + script
	exception.code = code
	return exception

## 検査の対象を固定ファイルの分だけにする。
func _fixture_errors(closure: RefCounted) -> Array[String]:
	var result: Array[String] = []
	result.assign(closure.errors.filter(func(message: String) -> bool: return message.begins_with(DIR)))
	return result

func _has(errors: Array, text: String) -> bool:
	return errors.any(func(message: String) -> bool: return text in message)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
