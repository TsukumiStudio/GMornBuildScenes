#!/bin/sh
# このアドオンだけをヘッドレスで確かめる。音は出さない。
#
# リポジトリ直下に project.godot は置けない。submodule として取り込まれた先に
# project.godot があると、Godot がそこを別プロジェクトと見なして書き出しから外す。
# 代わりに一時の最小プロジェクトへ写して回す。
set -eu

addon_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
godot_bin=${GODOT_BIN:-$(command -v godot 2>/dev/null || echo /Applications/Godot.app/Contents/MacOS/Godot)}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

target="$work_dir/addons/gmorn_build_scenes"
mkdir -p "$target/tests"
cp "$addon_dir"/*.gd "$addon_dir"/*.gd.uid "$addon_dir/plugin.cfg" "$target/"
# tests/.gdignore は取り込んだ先で検査用の素材を読ませないためのもの。ここでは読ませる。
cp -R "$addon_dir/tests/fixture" "$target/tests/"
cp "$addon_dir/verify.gd" "$work_dir/verify.gd"

cat > "$work_dir/project.godot" <<'PROJECT'
config_version=5

[application]

config/name="GMornBuildScenes Verify"
config/features=PackedStringArray("4.7")

[editor_plugins]

enabled=PackedStringArray("res://addons/gmorn_build_scenes/plugin.cfg")

[gmorn_build_scenes]

profiles=PackedStringArray("res://addons/gmorn_build_scenes/tests/fixture/profile_demo.tres", "res://addons/gmorn_build_scenes/tests/fixture/profile_broken.tres")
PROJECT

# 書き出し: 検査を通る profile は閉包だけを入れ、検査に失敗する profile は成果物を残さない。
cat > "$work_dir/export_presets.cfg" <<'PRESETS'
[preset.0]

name="Demo"
platform="Linux"
runnable=true
custom_features="verify_demo"
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""

[preset.0.options]

binary_format/embed_pck=false

[preset.1]

name="Broken"
platform="Linux"
runnable=false
custom_features="verify_broken"
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""

[preset.1.options]

binary_format/embed_pck=false
PRESETS

cat > "$work_dir/check_pack.gd" <<'CHECK'
extends SceneTree
# 書き出した pack に、閉包のファイルだけが入っていること。
func _initialize() -> void:
	var fixture := "res://addons/gmorn_build_scenes/tests/fixture/"
	var missing := ["clean.tscn", "clean.json", "shared.tres"].filter(func(name: String) -> bool: return not ResourceLoader.exists(fixture + name) and not FileAccess.file_exists(fixture + name))
	var leaked := ["root.tscn", "untyped.tres", "dynamic.tres", "chain_a.tres"].filter(func(name: String) -> bool: return ResourceLoader.exists(fixture + name) or FileAccess.file_exists(fixture + name))
	if not missing.is_empty() or not leaked.is_empty():
		printerr("pack: missing %s, leaked %s" % [missing, leaked])
		quit(1)
		return
	print("pack: ok")
	quit(0)
CHECK

fail() { echo "verify: $1" >&2; exit 1; }
"$godot_bin" --headless --editor --path "$work_dir" --quit > "$work_dir/import.log" 2>&1 || fail "import に失敗"
if grep -E "ERROR|WARNING|Parse Error" "$work_dir/import.log"; then fail "import でエラー"; fi
"$godot_bin" --headless --audio-driver Dummy --path "$work_dir" --script verify.gd

"$godot_bin" --headless --path "$work_dir" --export-pack Demo "$work_dir/demo.pck" > "$work_dir/demo.log" 2>&1
[ -s "$work_dir/demo.pck" ] || fail "検査を通る書き出しの成果物が無い"
empty_dir=$(mktemp -d)
(cd "$empty_dir" && "$godot_bin" --headless --main-pack "$work_dir/demo.pck" --script "$work_dir/check_pack.gd") || fail "書き出しの中身が閉包と違う"
rmdir "$empty_dir"

"$godot_bin" --headless --path "$work_dir" --export-pack Broken "$work_dir/broken.pck" > "$work_dir/broken.log" 2>&1 || true
[ ! -e "$work_dir/broken.pck" ] || fail "検査に失敗した書き出しの成果物が残った"
grep -q "検査に失敗したので" "$work_dir/broken.log" || fail "検査に失敗した書き出しがエラーを出さない"
echo "verify: ok"
