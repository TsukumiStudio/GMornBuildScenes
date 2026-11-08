#!/bin/sh
# このアドオンをヘッドレスで確かめる。音は出さない。
#   ./verify.sh                 GODOT_BIN で Godot の実行ファイルを指定できる
#
# リポジトリ直下に project.godot は置けない (取り込んだ先で別プロジェクトと見なされ、書き出しから外れる)。
# そのため一時フォルダーに合成プロジェクトを2つ組んで回す。
#   A: addons/gmorn_build_scenes に置き、閉包と検査の単体テスト (verify.gd) と書き出しを確かめる。
#   B: addons/vendor/build_scenes に置き、main scene・autoload・class_name・シェーダーの include・
#      生のテキスト・収録外のレベルがある構成で、書き出した pack を起動するまでを確かめる。
set -eu

addon_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
godot=${GODOT_BIN:-$(command -v godot 2>/dev/null || echo /Applications/Godot.app/Contents/MacOS/Godot)}
root=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$root"' EXIT
[ -z "${KEEP:-}" ] || echo "verify: 作業フォルダー $root"

fail() { echo "verify: $1" >&2; exit 1; }

# $1 プロジェクト, $2 アドオンを置く res:// からのフォルダー
install_addon() {
	mkdir -p "$1/$2"
	cp "$addon_dir"/*.gd "$addon_dir"/*.gd.uid "$addon_dir/plugin.cfg" "$1/$2/"
}

# $1 プロジェクト。import でエラー・警告が出たら止める。
import_project() {
	"$godot" --headless --editor --path "$1" --quit > "$1/import.log" 2>&1 || fail "$1 の import に失敗"
	if grep -E "ERROR|WARNING|Parse Error" "$1/import.log"; then fail "$1 の import でエラー"; fi
}

# $1 プロジェクト, $2 機能タグ, $3 期待する終了コード
preflight() {
	code=0
	"$godot" --headless --path "$1" --script "res://$addon/preflight.gd" -- --features="$2" > "$1/preflight.log" 2>&1 || code=$?
	[ "$code" = "$3" ] || { cat "$1/preflight.log"; fail "preflight --features=$2 が $code で終わった (期待 $3)"; }
}

# $1 プロジェクト, $2 preset 名, $3 機能タグ
write_preset() {
	cat >> "$1/export_presets.cfg" <<PRESET
[preset.$4]

name="$2"
platform="Linux"
runnable=false
custom_features="$3"
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""

[preset.$4.options]

binary_format/embed_pck=false

PRESET
}

# $1 pack, $2 確かめるスクリプト。pack だけで動かす (プロジェクトのフォルダーを読ませない)。
run_pack() {
	empty=$(mktemp -d "$root/run.XXXXXX")
	(cd "$empty" && "$godot" --headless --main-pack "$1" ${2:+--script "$2"}) > "$1.log" 2>&1 || { cat "$1.log"; fail "$1 を起動できない"; }
	if grep -E "ERROR|SCRIPT ERROR" "$1.log"; then fail "$1 の起動でエラー"; fi
}

# --- A ---
a="$root/a"
addon=addons/gmorn_build_scenes
install_addon "$a" "$addon"
# tests/.gdignore は取り込んだ先で検査用の素材を読ませないためのもの。ここでは読ませる。
mkdir -p "$a/$addon/tests"
cp -R "$addon_dir/tests/fixture" "$a/$addon/tests/"
cp "$addon_dir/verify.gd" "$a/verify.gd"
cat > "$a/project.godot" <<PROJECT
config_version=5

[application]

config/name="GMornBuildScenes A"
config/features=PackedStringArray("4.7")

[editor_plugins]

enabled=PackedStringArray("res://$addon/plugin.cfg")

[gmorn_build_scenes]

profiles=PackedStringArray("res://$addon/tests/fixture/profile_demo.tres", "res://$addon/tests/fixture/profile_broken.tres")
PROJECT
write_preset "$a" Demo verify_demo 0
write_preset "$a" Broken verify_broken 1
import_project "$a"
"$godot" --headless --audio-driver Dummy --path "$a" --script verify.gd

preflight "$a" verify_demo 0
preflight "$a" verify_broken 1
preflight "$a" no_such_build 1
preflight "$a" verify_demo,verify_broken 1
grep -q "複数ある" "$a/preflight.log" || fail "複数のプロファイルに当たる機能タグを止めない"
cp "$a/project.godot" "$a/project.godot.bak"
sed 's|profiles=PackedStringArray(|profiles=PackedStringArray("res://missing_profile.tres", |' "$a/project.godot.bak" > "$a/project.godot"
preflight "$a" verify_demo 1
grep -q "missing_profile.tres が見つからない" "$a/preflight.log" || fail "設定にある無いプロファイルを止めない"
mv "$a/project.godot.bak" "$a/project.godot"

"$godot" --headless --path "$a" --export-pack Demo "$root/a.pck" > "$a/export.log" 2>&1
[ -s "$root/a.pck" ] || fail "A: 検査を通る書き出しの成果物が無い"
cat > "$root/check_a.gd" <<'CHECK'
extends SceneTree
func _initialize() -> void:
	var dir := "res://addons/gmorn_build_scenes/tests/fixture/"
	var present := ["clean.tscn", "clean.json", "shared.tres", "clean.gd", "helper.gd"]
	var absent := ["root.tscn", "other.tscn", "untyped.tres", "dynamic.tres", "chain_a.tres", "profile_broken.tres"]
	var wrong := present.filter(func(name: String) -> bool: return not FileAccess.file_exists(dir + name) and not ResourceLoader.exists(dir + name))
	wrong.append_array(absent.filter(func(name: String) -> bool: return FileAccess.file_exists(dir + name) or ResourceLoader.exists(dir + name)))
	if not wrong.is_empty():
		printerr("A の pack の中身が違う: %s" % [wrong])
		quit(1)
		return
	quit(0)
CHECK
run_pack "$root/a.pck" "$root/check_a.gd"
"$godot" --headless --path "$a" --export-pack Broken "$root/broken.pck" > "$a/broken.log" 2>&1 || true
[ ! -e "$root/broken.pck" ] || fail "A: 検査に失敗した書き出しの成果物が残った"
grep -q "検査に失敗したので" "$a/broken.log" || fail "A: 検査に失敗した書き出しがエラーを出さない"

# --- B ---
b="$root/b"
addon=addons/vendor/build_scenes
install_addon "$b" "$addon"
(cd "$addon_dir/tests/project_b" && find . -type f) | while read -r file; do
	mkdir -p "$b/$(dirname "$file")"
	sed "s|{{ADDON}}|$addon|g" "$addon_dir/tests/project_b/$file" > "$b/$file"
done
mv "$b/project.godot.in" "$b/project.godot"
write_preset "$b" Level1 level_1 0
import_project "$b"
preflight "$b" level_1 0
"$godot" --headless --path "$b" --export-pack Level1 "$root/b.pck" > "$b/export.log" 2>&1
[ -s "$root/b.pck" ] || fail "B: 書き出しの成果物が無い"
cat > "$root/check_b.gd" <<'CHECK'
extends SceneTree
func _initialize() -> void:
	var present := ["main.tscn", "main.gd", "lib/greeter.gd", "autoload/settings.gd", "levels/level_1.tscn", "levels/level_1.gd",
		"shared/tile.tres", "shared/water.tres", "shaders/water.gdshader", "shaders/common.gdshaderinc", "data/notes.txt", "lib/greeting.tres",
		"addons/vendor/build_scenes/build_scenes.gd", "addons/vendor/build_scenes/build_assets.gd"]
	var absent := ["levels/level_2.tscn", "levels/level_2_only.tres"]
	var wrong := present.filter(func(name: String) -> bool: return not FileAccess.file_exists("res://" + name) and not ResourceLoader.exists("res://" + name))
	wrong.append_array(absent.filter(func(name: String) -> bool: return FileAccess.file_exists("res://" + name) or ResourceLoader.exists("res://" + name)))
	if not wrong.is_empty():
		printerr("B の pack の中身が違う: %s" % [wrong])
		quit(1)
		return
	quit(0)
CHECK
run_pack "$root/b.pck" "$root/check_b.gd"
run_pack "$root/b.pck"
grep -q "project_b: hello" "$root/b.pck.log" && grep -q "project_b: started Level1 tile" "$root/b.pck.log" || { cat "$root/b.pck.log"; fail "B: pack の main scene が最後まで動かない"; }
echo "verify: ok"
