# GMornBuildScenes

Godot の書き出しに入れるシーンを、Unity の Build Settings (Scenes In Build) のようにプロファイルで選ぶアドオン。
入るのは選んだルートシーンと、そこから型付きの参照で辿れるファイルだけ。たとえば体験版のプロファイルに 1 面だけを入れれば、2 面以降の素材は書き出しに入らない。

文字列のパスで素材を読むコードは、どの素材が要るかを書き出し時に知る手段がないので禁止する。素材はシーンに型付きで持たせ、実行時はそこから引く。違反は書き出しの前の検査 (preflight) が終了コード 1 で止める。

Godot 4.7 で確認した。1〜5 章は導入時に通して読み、6 章以降は困ったときに引く。

## 1. 最短の導入: submodule で入れ、プロファイルを1つ作り、preflight を通す

```sh
git submodule add https://github.com/TsukumiStudio/GMornBuildScenes.git addons/gmorn_build_scenes
```

置き場所は `addons/` の下ならどこでもよい (アドオン内の参照はすべて相対パス)。clone し直した人は `git submodule update --init --recursive`、新しい版へ上げるときは `git submodule update --remote addons/gmorn_build_scenes` を使う。`.gitmodules` のこの submodule に `ignore = untracked` を書いておくと、Godot が生成する `.uid` で親リポジトリの状態が汚れない。

続けて Project Settings → Plugins で GMornBuildScenes を有効にする。あとは 2 章のとおりプロファイルを作り、5 章の preflight が 0 で終わることを確かめれば導入は終わる。

## 2. プロファイルはインスペクタで作る

1. FileSystem で新しい Resource を作り、script に `build_profile.gd` を付けて保存する (例: `res://build/demo.tres`)。
2. インスペクタで3項目を埋める。

   | 項目 | 例 | 意味 |
   | --- | --- | --- |
   | `feature` | `demo` | このプロファイルを使う書き出しの機能タグ。Export の preset の Features → Custom に同じ名前を入れる |
   | `root_scenes` | `res://levels/level_1.tscn` | 収録するルートシーン。ここから辿れるものが一緒に入る |
   | `path_access_exceptions` | (空) | パスで読み込む行の例外。7 章を参照 |

3. Project Settings → General → Gmorn Build Scenes → Profiles に、作ったプロファイルを足す。

プロファイルが1つでもあると、機能タグがどのプロファイルにも当たらない書き出しは失敗する。黙って全ファイル入りの書き出しにはしない。製品版も含め、書き出す版ごとにプロファイルを作る。書き出しには選ばれたプロファイルだけが入る。

## 3. 依存はシーンの型付き参照で書く

書き出しの検査が辿るのは次の参照だけ。

- シーン・リソースの外部参照 (`ext_resource`)。参照先の参照も辿る
- スクリプトの `preload("...")`・`extends "..."`・`class_name` の利用
- シェーダーの `#include "..."`
- main scene・autoload・テーマなど、プロジェクト設定が名指すファイル

画面に出さない素材 (レベルの JSON、効果音、差し替え用の画像など) は、ルートシーンに `Node` を足して script に `build_dependencies.gd` を付け、インスペクタの `resources` に入れる。実行時は `build_assets.gd` でパスを鍵に引く。

```gdscript
const BuildAssets := preload("res://addons/gmorn_build_scenes/build_assets.gd")

func _ready() -> void:
	var level: Dictionary = BuildAssets.json("res://levels/level_1.json")
	var icon := BuildAssets.find("res://ui/lives.png") as Texture2D
```

`find` はシーンが持っている素材を返すだけで、ファイルを読みに行かない。持っていなければエラーを出して `null` を返す。`json` は複製を返すので、書き換えても他のシーンが持つ同じ素材には響かない。JSON に書いたパスは、この引き当ての鍵としてだけ使う。

別のルートシーンへ移るときは `build_scenes.gd` の `load_root(path)` を使う。収録されていないシーンなら、理由を出して `null` を返す。

## 4. パスで読み込むコードは書き出し前に止まる

閉包 (ルートシーンから辿れたファイルの集まり) の中のスクリプトに、次の呼び出しがあると検査が止める。

`load(` ・ `ResourceLoader.load(` ・ `ResourceLoader.load_threaded_request(` ・ `FileAccess.open(` ・ `FileAccess.get_file_as_string(` ・ `FileAccess.get_file_as_bytes(` ・ `DirAccess.open(` ・ `DirAccess.get_files_at(` ・ `DirAccess.get_directories_at(`

止めない行は次のとおり。

- `user://` を含む行 (セーブや設定の読み書き)
- `.resource_path` を使う行 (型付きの参照から取ったパス)
- `# build_scenes: allow <理由>` を書いた行。エディタ専用の道具だけに使う

閉包の中のファイルに書かれた `res://` の文字列も検査する。指す素材が書き出しに入らないなら止める。ただし、どこにも無いファイル名 (書式文字列や元データの記録) とフォルダーは見ない。Resource でない生のファイル (`.txt`、`importer="keep"` の `.csv` など) は文字列でしか名指せないので、閉包の中の文字列が名指せば書き出しに入れる。

## 5. CI と CLI では書き出しの前に必ず preflight を走らせる

```sh
godot --headless --path . --script res://addons/gmorn_build_scenes/preflight.gd -- --preset="Web"
godot --headless --path . --export-release "Web" build/web/index.html
```

`--preset` には `export_presets.cfg` の `name` を渡す。機能タグを直接渡すなら `--features=demo` と書く。検査に通れば、プロファイルと書き出すファイル数を出して 0 で終わる。通らなければ理由を出して 1 で終わる。

**preflight を飛ばして直接書き出すと、検査に失敗しても終了コードは 0 になる。** Godot の書き出しプラグインには、書き出しを失敗させる手段がない。プラグインにできるのは、エラーを出し、ファイルを何も入れず、最後に成果物 (書き出し先と、その横の `.pck`) を消すところまで。CI で終了コードを頼りに止めたいなら preflight が要る。

## 6. エラーが出たら (逆引き)

| 出たエラー | 直し方 |
| --- | --- |
| `パスで読み込んでいる` | 読む素材をシーンの `BuildDependencies` に入れ、`BuildAssets.find` / `json` で引く。`user://` などの正当な IO なら 7 章の例外にする |
| `を文字列でしか名指していないので書き出しに入らない` | その素材をシーンの外部参照・`preload`・型付きの `@export`・`BuildDependencies` のどれかで持たせる |
| `が参照する ... が見つからない` | 参照先のファイルを戻すか、参照を直す |
| `は .gdignore のあるフォルダーにあり、書き出されない` | `.gdignore` のフォルダーの外へ素材を移すか、参照をやめる |
| `機能タグ ... に当たるプロファイルが無い` | preset の Features → Custom とプロファイルの `feature` をそろえる。新しい版ならプロファイルを作る |
| `機能タグ ... に当たるプロファイルが複数ある` | 1つの書き出しに当たるプロファイルを1つにする |
| `gmorn_build_scenes/profiles の ... が見つからない` | Project Settings の Profiles から消えたファイルを外す |
| `例外にした行が見つからない` | 例外にした行が書き換わった。新しい行を確かめて、例外の `code` を直すか例外を消す |
| `ルートシーン ... が見つからない` / `root_scenes が空` | プロファイルの `root_scenes` を直す |

## 7. 例外は1行ずつ、中身まで一致したときだけ許す

型付きの参照にできない正当なパス読み込み (外部アドオンのセーブ処理など) は、`path_access_exception.gd` の Resource で1行ずつ許す。`script_path` (スクリプトのパス) と `code` (前後の空白を除いた行の中身) が両方一致した行だけが通る。`reason` には理由を書く。

行が書き換わると例外は効かなくなり、使われなくなった例外も検査が止める。例外が古いまま残り、新しく足した読み込みを素通りさせる事故を防ぐため。

## 8. 制限と、保証しないこと

- **スクリプト (`.gd`) は閉包の外でも書き出しに入る。** Godot 4.7 はスクリプトを書き出しプラグインに渡さず別の経路で書き出すため、このアドオンでは外せない。外れるのはシーン・リソース・画像・音声・JSON などのファイル。
- 検査は GDScript を1行ずつ文字の並びで照合する。変数に入れたパスや、別の関数へ渡して読むパスは、読み込む呼び出しのある行でしか見つからない。任意のコードを解析できるわけではない。
- `class_name` は名前の一致で拾う。使っていない同名の語でも、そのスクリプトが閉包に入る。
- 成果物を消す処理を確かめたのは pack の書き出し (`--export-pack`) だけ。実行ファイル・Web の書き出しと、Editor の Export ダイアログからの書き出しでは確かめていない。
- `build_assets.gd` の `tool_loading` を立てたとき (と Editor の中) は、持っていない素材もパスで読む。シーン生成器のようなエディタ専用の道具だけが立てる。
- 確かめたのは Godot 4.7 と GDScript だけ。他の版と C# では試していない。
- 検査が通っても、実行してはじめて分かる欠けは残りうる。書き出した成果物で代表のプレイを通して確かめる。

## 9. このアドオンの確かめ方

```sh
./verify.sh   # GODOT_BIN で Godot の実行ファイルを指定できる
```

一時フォルダーに合成プロジェクトを2つ組んで回す。

- **A**: 単体テストと書き出しを確かめる。参照の連鎖、互いに preload し合うスクリプト、2つのルートが共有する素材、収録外の除外、欠けた参照、禁止した読み込み、例外の照合を扱う。
- **B**: アドオンを `addons/vendor/build_scenes` に置き、main scene・autoload・`class_name`・シェーダーの `#include`・生のテキスト・収録外のレベルがある構成を扱う。書き出した pack だけで起動するところまで確かめる。

`tests/` には `.gdignore` があるので、取り込んだ先の Godot はこのフォルダーを読まない。

## ライセンス

[UNLICENSE](UNLICENSE)
