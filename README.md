# GMornBuildScenes

Godot の書き出しに入れるシーンを、Unity の Build Settings (Scenes In Build) のようにプロファイルで選ぶアドオン。
入るのは選んだルートシーンと、そこから型付きの参照で辿れるファイルだけ。体験版のプロファイルに 1 面だけを入れれば、2 面以降の素材は書き出しに入らない。

文字列のパスで素材を読むコードは、どの素材が要るかを書き出し時に知る手段がないので禁止する。素材はシーンに型付きで持たせ、実行時はそこから引く。違反は書き出しの前の検査 (preflight) が終了コード 1 で止める。

確かめたのは Godot 4.7 と GDScript。

## クイックスタート

`res://levels/level_1.tscn` だけを入れた体験版を、Linux 向けに書き出すまでの手順。

**1. アドオンを入れる**

```sh
git submodule add https://github.com/TsukumiStudio/GMornBuildScenes.git addons/gmorn_build_scenes
```

**2. プラグインを有効にする**

Editor の Project → Project Settings → Plugins で、GMornBuildScenes の Enabled をオンにする。

**3. プロファイルを作る**

次の内容を `res://build/demo.tres` に保存する (インスペクタで作る手順は「3. プロファイルを作る」)。

```
[gd_resource type="Resource" format=3]

[ext_resource type="Script" path="res://addons/gmorn_build_scenes/build_profile.gd" id="1"]

[resource]
script = ExtResource("1")
feature = "demo"
root_scenes = Array[String](["res://levels/level_1.tscn"])
```

Project Settings → General → Gmorn Build Scenes → Profiles に `res://build/demo.tres` を足す。

**4. 書き出し preset に機能タグを付ける**

Project → Export で Linux の preset を作り、Features タブの Custom に `demo` と書く。

**5. 検査して書き出す**

```sh
godot --headless --path . --script res://addons/gmorn_build_scenes/preflight.gd -- --preset="Linux" --export-release=build/demo/game.x86_64
```

検査に通れば `GMornBuildScenes preflight: res://build/demo.tres 〇 ファイル` と出て書き出しが始まる。終了コードは書き出しのもの。通らなければ理由を出して 1 で終わる。理由の読み方は「困ったとき」の表を見る。

## 詳しい手順

### 1. 入れる・上げる

submodule で入れるのがおすすめ (上のクイックスタート)。置き場所は `addons/` の下ならどこでもよい。アドオン内の参照はすべて相対パスなので、`addons/vendor/build_scenes` のような別の場所でも動く。

| したいこと | コマンド |
| --- | --- |
| clone し直した後に中身を取る | `git submodule update --init --recursive` |
| 新しい版へ上げる | `git submodule update --remote addons/gmorn_build_scenes` |
| `.uid` で親リポジトリの状態が汚れないようにする | `git config -f .gitmodules submodule.addons/gmorn_build_scenes.ignore untracked` |

submodule を使わないなら、このリポジトリの中身をそのまま `addons/gmorn_build_scenes/` へ写す。`tests/` には `.gdignore` があるので、写しても Godot は読まない。

### 2. プラグインを有効にする

Project → Project Settings → Plugins で GMornBuildScenes の Enabled をオンにする。`project.godot` には次の行が書かれる。CI 用に手で書く場合も同じ。

```
[editor_plugins]

enabled=PackedStringArray("res://addons/gmorn_build_scenes/plugin.cfg")
```

### 3. プロファイルを作る

プロファイルは「どの書き出しに、どのルートシーンを入れるか」を決める Resource。書き出す版ごとに1つ作る。製品版も例外ではない。プロファイルが1つでもあると、どのプロファイルにも当たらない書き出しは失敗するため。

インスペクタで作る手順:

1. FileSystem で右クリック → 新規作成 → リソース… を選び、型に `Resource` を選んで保存する (例: `res://build/demo.tres`)。
2. インスペクタの一番下にある Script に `build_profile.gd` をドラッグする。
3. 現れた3項目を埋める。

   | 項目 | 例 | 意味 |
   | --- | --- | --- |
   | `feature` | `demo` | このプロファイルを使う書き出しの機能タグ |
   | `root_scenes` | `res://levels/level_1.tscn` | 収録するルートシーン。ここから辿れるものが一緒に入る |
   | `path_access_exceptions` | (空のまま) | パスで読み込む行の例外。「6. パスで読み込むコードと例外」を参照 |

最後に Project Settings → General → Gmorn Build Scenes → Profiles へ足す。`project.godot` では次の行になる。

```
[gmorn_build_scenes]

profiles=PackedStringArray("res://build/demo.tres", "res://build/full.tres")
```

書き出しには選ばれたプロファイルだけが入る。

### 4. 書き出し preset に機能タグを付ける

Project → Export で preset を選び、Features タブの Custom にプロファイルの `feature` と同じ名前を書く。`export_presets.cfg` では `custom_features="demo"` になる。1つの書き出しに当たるプロファイルは、ちょうど1つでなければならない。

### 5. 依存を型付きの参照で書く

書き出しの検査は、ルートシーンから次の参照を辿って閉包 (書き出しに入れるファイルの集まり) を作る。

- シーン・リソースの外部参照 (`ext_resource`)。参照先の参照も辿る
- スクリプトの `preload("...")`・`extends "..."`・`class_name` の利用
- シェーダーの `#include "..."`
- main scene・autoload・テーマなど、プロジェクト設定が名指すファイル

画面に出さない素材 (レベルの JSON、効果音、差し替え用の画像など) は、ルートシーンに置いた依存ホルダーに持たせる。

1. ルートシーンに `Node` を足し、Script に `build_dependencies.gd` をドラッグする。
2. インスペクタの `resources` に素材をドラッグする。
3. 実行時は `build_assets.gd` で、パスを鍵に引く。

```gdscript
const BuildAssets := preload("res://addons/gmorn_build_scenes/build_assets.gd")

func _ready() -> void:
	var level: Dictionary = BuildAssets.json("res://levels/level_1.json")
	var icon := BuildAssets.find("res://ui/lives.png") as Texture2D
```

`find` は、いま instantiate されているシーンが持つ素材を返すだけで、ファイルを読みに行かない。持っていなければエラーを出して `null` を返す。`json` は複製を返すので、書き換えても他のシーンが持つ同じ素材には響かない。

別のルートシーンへ移るときは `build_scenes.gd` の `load_root(path)` を使う。収録されていないシーンなら理由を出して `null` を返す。Editor から実行したとき (機能タグが無いとき) は、すべてのシーンを収録扱いにする。

### 6. パスで読み込むコードと例外

閉包の中のスクリプトに次の呼び出しがあると、検査が止める。

`load(` ・ `ResourceLoader.load(` ・ `ResourceLoader.load_threaded_request(` ・ `FileAccess.open(` ・ `FileAccess.get_file_as_string(` ・ `FileAccess.get_file_as_bytes(` ・ `DirAccess.open(` ・ `DirAccess.get_files_at(` ・ `DirAccess.get_directories_at(`

次の行は止めない。

- `user://` を含む行 (セーブや設定の読み書き)
- `.resource_path` を使う行 (型付きの参照から取ったパス)
- `# build_scenes: allow <理由>` を書いた行。エディタ専用の道具だけに使う

閉包の中のファイルに書かれた `res://` の文字列も検査し、指す素材が書き出しに入らないなら止める。どこにも無いファイル名 (書式文字列や元データの記録) とフォルダーは見ない。Resource でない生のファイル (`.txt`、`importer="keep"` の `.csv` など) は文字列でしか名指せないので、閉包の中の文字列が名指せば書き出しに入れる。

外部アドオンのセーブ処理のように、型付きの参照にできない正当な読み込みは例外にする。`path_access_exception.gd` を Script にした Resource を作り、`script_path` (スクリプトのパス)・`code` (前後の空白を除いた行の中身)・`reason` (理由) を埋めて、プロファイルの `path_access_exceptions` に足す。`script_path` と `code` が両方一致した行だけが通る。行が書き換わると例外は効かなくなり、使われなくなった例外も検査が止める。古い例外が新しい読み込みを素通りさせないため。

### 7. 書き出す (手元と CI)

書き出しは preflight に任せる。

```sh
# 検査だけ
godot --headless --path . --script res://addons/gmorn_build_scenes/preflight.gd -- --preset="Linux"
# 検査して書き出す
godot --headless --path . --script res://addons/gmorn_build_scenes/preflight.gd -- --preset="Linux" --export-release=build/demo/game.x86_64
```

| オプション | 意味 |
| --- | --- |
| `--preset=<名前>` | `export_presets.cfg` の preset の `name`。機能タグもここから読む |
| `--features=a,b` | preset を使わずに機能タグを直接渡す (検査だけのとき) |
| `--export-release` / `--export-debug` / `--export-pack` | 検査に通ったら続けて書き出す。`=出力先` を省くと preset の `export_path` に書く。出力先のフォルダーが無ければ作る |

preflight で書き出すと、閉包の外のスクリプト (`.gd`) も書き出しから外れる。Godot 4.7 はスクリプトを書き出しプラグインに渡さずに書き出すので、preflight がその preset の `exclude_filter` に一時的に足してから書き出し、終わったら `export_presets.cfg` を元の内容に戻す。

CI (GitHub Actions) では、submodule ごと checkout し、import してから preflight で書き出す。preflight のスクリプト自体が読み込めないと Godot は 0 で終わるので、ログの `SCRIPT ERROR` でも失敗にする。

```yaml
- uses: actions/checkout@v4
  with:
    submodules: recursive
- run: godot --headless --path . --import
- shell: bash
  run: |
    set -o pipefail
    godot --headless --path . --script res://addons/gmorn_build_scenes/preflight.gd -- --preset="Linux" --export-release 2>&1 | tee export.log
    ! grep -q "SCRIPT ERROR" export.log
```

**preflight を通さずに直接書き出すと、検査に失敗しても終了コードは 0 になり、閉包の外のスクリプトも入る。** Godot の書き出しプラグインには、書き出しを失敗させる手段がない。プラグインにできるのは、エラーを出し、ファイルを何も入れず、最後に成果物 (書き出し先と、その横の `.pck`) を消すところまで。Editor の Export ダイアログから書き出すときも同じ。

## 困ったとき

| 出たエラー | 直し方 |
| --- | --- |
| `パスで読み込んでいる` | 読む素材をシーンの依存ホルダーに入れ、`BuildAssets.find` / `json` で引く。正当な IO なら例外にする (詳しい手順の 6) |
| `を文字列でしか名指していないので書き出しに入らない` | その素材をシーンの外部参照・`preload`・型付きの `@export`・依存ホルダーのどれかで持たせる |
| `が参照する ... が見つからない` | 参照先のファイルを戻すか、参照を直す |
| `は .gdignore のあるフォルダーにあり、書き出されない` | `.gdignore` のフォルダーの外へ素材を移すか、参照をやめる |
| `機能タグ ... に当たるプロファイルが無い` | preset の Features → Custom とプロファイルの `feature` をそろえる。新しい版ならプロファイルを作る |
| `機能タグ ... に当たるプロファイルが複数ある` | 1つの書き出しに当たるプロファイルを1つにする |
| `gmorn_build_scenes/profiles の ... が見つからない` | Project Settings の Profiles から、消えたファイルを外す |
| `ルートシーン ... が見つからない` / `root_scenes が空` | プロファイルの `root_scenes` を直す |
| `例外にした行が見つからない` | 例外にした行が書き換わった。新しい行を確かめて `code` を直すか、例外を消す |
| `preset ... が無い` | `--preset=` の名前を `export_presets.cfg` の `name` に合わせる |
| `書き出すには --preset= で preset を指定する` | `--features=` ではなく `--preset=` で書き出す preset を渡す |
| `export_presets.cfg.gmorn_build_scenes_backup が残っている` | 前の書き出しが途中で止まった。バックアップと `export_presets.cfg` を見比べて戻し、バックアップを消す |
| 実行時に `を型付きで持つシーンが無い` | その素材を、いま開いているシーンの依存ホルダーに入れる |

## 制限と、保証しないこと

- 閉包の外のスクリプトを外せるのは、preflight に書き出しまで任せたときだけ。
- preflight のスクリプト自体が読み込めない (アドオンが壊れている) と、Godot は終了コード 0 で終わる。CI ではログの `SCRIPT ERROR` も見る (詳しい手順の 7)。
- 検査は GDScript を1行ずつ文字の並びで照合する。変数に入れたパスや、別の関数へ渡して読むパスは、読み込む呼び出しのある行でしか見つからない。任意のコードを解析できるわけではない。
- `class_name` は名前の一致で拾う。使っていない同名の語でも、そのスクリプトが閉包に入る。
- 直接書き出して検査に失敗したとき、成果物を消す処理を確かめたのは pack の書き出し (`--export-pack`) だけ。
- `build_assets.gd` の `tool_loading` を立てたとき (と Editor の中) は、持っていない素材もパスで読む。シーン生成器のようなエディタ専用の道具だけが立てる。
- 他の Godot の版と C# では試していない。
- 検査が通っても、実行してはじめて分かる欠けは残りうる。書き出した成果物で代表のプレイを通して確かめる。

## このアドオンの確かめ方

```sh
./verify.sh   # GODOT_BIN で Godot の実行ファイルを指定できる
```

一時フォルダーに合成プロジェクトを2つ組んで回す。A では単体テストと書き出し (参照の連鎖・循環・共有・除外・欠けた参照・禁止した読み込み・例外) を確かめる。B ではアドオンを `addons/vendor/build_scenes` に置く。main scene・autoload・`class_name` と継承・シェーダーの `#include`・生のテキスト・未使用のスクリプトがある構成で、preflight で書き出した pack だけで起動するところまで確かめる。

## ライセンス

[UNLICENSE](UNLICENSE)
