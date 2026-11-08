# GMornBuildScenes

## 概要

Unity の Build Settings (Scenes In Build) のように、書き出しに入れるルートシーンをインスペクタで選ぶ Godot アドオン。
書き出しに入るのは、ルートシーンと、そこから型付きの参照で辿れるものだけ。実行時もファイルをパスで読まず、シーンが型付きで持つ素材を引く。

## 動作環境

- Godot 4.7 で確認 (headless の書き出しは pack (`--export-pack`) で確認)。
- アドオンの外の道具は要らない。

## 何ができるか

- **ビルドプロファイル**: 機能タグ (Export の Features → Custom) ごとに、収録するルートシーンを選ぶ。
- **型付きの依存だけを書き出す**: シーン・リソースの外部参照 (再帰)、スクリプトの `preload`・`extends`・`class_name` の利用、シェーダーの `#include`、main scene・autoload・プロジェクト設定が名指すものを辿る。循環と共有は1度ずつ入る。選ばれたプロファイルだけが入る。
- **書き出し前の検査 (preflight)**: 書き出しに入らない素材を文字列のパスで名指していたり、パスで読み込むコードがあったりすれば、終了コード 1 で止まる。
- **実行時の取得**: シーンに置いた `BuildDependencies` が型付きで持つ素材を、`res://` パスを鍵に引く。ファイルは読まない。

## 使い方

### 1. 取り込む

アドオン一式をリポジトリ直下に置いてある。取り込む側の `addons/gmorn_build_scenes` へ submodule として足す。

```sh
git submodule add https://github.com/TsukumiStudio/GMornBuildScenes.git addons/gmorn_build_scenes
# 取り込んだリポジトリを clone した人は
git submodule update --init --recursive
# 新しい版へ上げるとき
git submodule update --remote addons/gmorn_build_scenes
```

`.gitmodules` のこの submodule に `ignore = untracked` を足すと、Godot が作る `.uid` で親の状態が汚れない。

**リポジトリ直下に `project.godot` は置かない。** 置くと Godot がそこを別のプロジェクトと見なし、取り込んだ側の書き出しからフォルダごと外れる。

### 2. 有効にする

Project Settings → Plugins で GMornBuildScenes を有効にする。

### 3. ビルドプロファイルを作る (インスペクタ)

1. FileSystem で新しい Resource を作り、script に `build_profile.gd` を付けて保存する (例 `res://build/profiles/demo.tres`)。
2. インスペクタで決める。
   - `feature`: このプロファイルを使う書き出しの機能タグ。Export の preset の Features → Custom に同じ名前を入れる。
   - `root_scenes`: 収録するルートシーン。
   - `path_access_exceptions`: パスで読み込む行の例外 (下の「6. 例外」)。
3. Project Settings → General → Gmorn Build Scenes → Profiles にプロファイルを足す。

プロファイルが1つでもあると、どのプロファイルにも当たらない書き出しは失敗にする (黙って全部入りにしない)。

### 4. 画面に出さない素材をシーンに持たせる

ルートシーンに `Node` を足して script に `build_dependencies.gd` を付け、インスペクタの `resources` に素材 (JSON・画像・音声・スクリプトなど) を入れる。
実行時は `build_assets.gd` で引く。

```gdscript
const BuildAssets := preload("res://addons/gmorn_build_scenes/build_assets.gd")

func _ready() -> void:
	var level: Dictionary = BuildAssets.json("res://levels/level_1.json")
	var icon := BuildAssets.find("res://ui/lives.png") as Texture2D
```

- `find(path)`・`json(path)`・`has(path)` は、instantiate 済みの `BuildDependencies` が持つ素材だけを引く。持っていなければ `find` はエラーを出して `null` を返す。
- `json` は複製を返す。書き換えても持っている素材は変わらない。
- データ (JSON) に書いたパスは、素材の識別子としてだけ使う。
- 収録ルートシーンへの遷移は `build_scenes.gd` の `load_root(path)`。収録外は `null` を返して理由を出す。

### 5. 書き出しの前に検査する (必須)

```sh
godot --headless --path . --script res://addons/gmorn_build_scenes/preflight.gd -- --preset="<export_presets.cfg の name>"
# 機能タグを直接渡すとき
godot --headless --path . --script res://addons/gmorn_build_scenes/preflight.gd -- --features=demo
```

失敗なら理由を出して 1 で終わる。CI では書き出しの前に必ず走らせる。

### 6. 例外

パスで読み込む行は `path_access_exception.gd` の Resource で1行ずつ許す。

- `script_path` と `code` (前後の空白を除いた行の中身) が両方一致する行だけ。`reason` に理由を書く。
- 行が変わると止まる。使われなくなった例外も止まる。
- `user://` のセーブなど、型付きの参照にできない正当なものだけに使う。

次の行は例外が要らない。

- `user://` を含む行と、`.resource_path` を使う行 (型付きの参照から取ったパス)。
- `# build_scenes: allow <理由>` を書いた行。エディタ専用の道具と、このアドオン自身の読み込みに使う。
- 型を持たない生のファイル (`importer="keep"` の csv、txt、バイト列) の名指し。閉包の中の文字列が名指せば入る。
- `.gdignore` の置き場は Godot が書き出さないので、そこを名指す文字列は記録として扱う。型付きの参照は止める。

## 方針: パスで読まない

収録は型付きの参照で決まる。文字列のパスや JSON に書いたパスで素材を読むのは禁止する。書き出しの検査で止めるもの:

- 閉包の中のファイルに書いた `res://` の文字列が、書き出しに入らない素材を指す。どこにも無いファイル名 (書式文字列や元データの記録) とフォルダは見ない。
- 閉包の中のスクリプトの、パスで読み込む呼び出し (`load(`・`ResourceLoader.load(`・`load_threaded_request(`・`FileAccess.open(`・`get_file_as_string(`・`get_file_as_bytes(`・`DirAccess.open(`・`get_files_at(`・`get_directories_at(`)。
- ルートシーン・依存が無い。例外の行が見つからない。どのプロファイルにも当たらない。

## 制限・保証しないこと

- **preflight を通さない書き出しは終了コード 0 で終わる。** `EditorExportPlugin` には書き出しを失敗にする API が無い。検査に失敗した書き出しでは、エラーを出し、全ファイルを外し、最後に成果物 (`path` と横の `.pck`) を消す。非0終了で止めるのは preflight の役目。
- 成果物を消すのを確かめたのは pack の書き出し (`--export-pack`) だけ。実行ファイルや Web の書き出し、Editor の Export ダイアログからの書き出しでは確かめていない。
- 検査は GDScript を行単位の字句で照合するだけで、任意のコードは解析できない。パスを変数や別の関数へ渡して読むと、読む側の行でしか見つからない。
- `class_name` は名前の一致で拾うので、使っていない同名の語でも入る。
- `build_assets.gd` の `tool_loading` を立てたとき (と Editor の中) は、持っていない素材も path で読む。エディタ専用の道具だけが立てる。
- 書き出した成果物で、代表のプレイを通して確かめること。検査が通っても、実行時にしか分からない欠けは残りうる。

## 確かめ方

```sh
./verify.sh   # GODOT_BIN で Godot の実行ファイルを指定できる
```

一時の最小プロジェクトへ写して、閉包と検査・実行時の取得・preflight の終了コード・書き出し (検査を通る profile は閉包だけ、失敗する profile は成果物なし) を確かめる。`tests/` は `.gdignore` で、取り込んだ先では読まれない。

## ライセンス

[UNLICENSE](UNLICENSE)
