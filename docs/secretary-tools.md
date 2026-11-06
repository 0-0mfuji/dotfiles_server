# 私用秘書の翻訳・Karakeepツール導入

2026-11-06にサーバーへ適用し、PLaMoの実GPU翻訳とKarakeepの参照接続を確認済み。
コードは `dotfile_infra` の `secretary/`、Mac側の転送準備はこのリポジトリの
`scripts/secretary-data-manifest` で管理する。

同日の確認結果:

- NanoMuse・Karakeep gateway・DSHの3サービスが稼働。
- NanoMuse・DSH・Codexそれぞれに129スキル。カタログ157件、欠落なし。
- PLaMoの英文→日本語翻訳がRTX 3070 Tiで成功。
- Karakeep参照に成功し、生のDELETEはgatewayでHTTP 403。
- Codex CLIを導入済み。CodexログインとDSHモデル認証は利用者による設定待ち。
- Macの移行対象101,165ファイル・53,872,680,057バイトを取り込み済み。
  取り込み時と配置後の再読み取りでSHA-256が全件一致。所有者secretary・mode600も確認済み。
  Macの原本とサーバーの非公開stagingは保持し、認証情報や仮想環境は移行対象から除外した。

認証情報・Git管理外のマシン設定・実行ログを除き、適用中に必要になった修正も
Macでコミット・pushしてからサーバーでpullした。サーバーだけのソース変更は残していない。

## 構成

同じ `secretary-dev` に以下を導入する。新しいコンテナや公開ポートは追加しない。

- DeepSeek Harness（既存開発環境と同じ固定版）を秘書ユーザーで追加。`dev secretary dsh` から開く。
- NanoMuse 1.0.7を維持。モデル接続・Vault・会話履歴・文書を保持。
- PLaMo 3 Translate 2B。公式モデルrevisionを固定。CUDA 12.6のPyTorchを専用venvへ導入。
- Karakeep-toolの公開済み導入用コミットを固定してクローン。Macの元checkoutは変更しない。
- 書籍・辞書・PDF・教材用Python環境、Karakeep CLI、YomiToku用venv、Chromium/Playwright、Java。
- 個別ツール126スキルと、Karakeep公式・データ調査・PLaMo翻訳の3スキル。
- MCP `secretary_tools`。一覧・ソース確認・CLI参照・辞書変換・翻訳・ジョブ実行・状態照会。

Karakeep-tool導入用ブランチ:
[0-0mfuji/Karakeep-tool: codex/secretary-tools](https://github.com/0-0mfuji/Karakeep-tool/tree/codex/secretary-tools)。
Macにあった未追跡の教材コードと必要な説明を別checkoutでコミットしたもの。
データ・認証・仮想環境や無関係のWebプロジェクトは含めない。
実際に取得するcommitは `dotfile_infra/secretary/versions.env` を参照。

## サーバー起動後の適用

Mac側のSSHエージェントを転送してサーバーへ接続する。秘密鍵はコンテナに置かない。

```bash
ssh -A dev-server
```

以下はサーバーで実行する。各リポジトリの作業中変更を確認し、変更がある場合は保全・整合してからpullする。

```bash
cd ~/dotfiles_server
git status --short
git pull --ff-only

cd ~/dotfile_infra
git status --short
git pull --ff-only
```

Git管理外の `terraform.tfvars` の既存 `secretary` オブジェクトで、IP・公開ポート等を維持しながら変更する。
既存tfvarsに4GiB/30GiBが明示されている場合、既定値の変更だけでは拡張されない。

```hcl
# secretary = { ... } の既存値に追記・変更する項目
cpu       = 4
memory    = "16GiB"
disk_size = "120GiB"
gpu       = true
nesting   = true  # DSHのbubblewrapサンドボックスに必要
```

Macの `data/` は確認時点で約43GB。モデル・venv・キャッシュに加え、他の書籍出力も置くため、
実際の転送対象容量とストレージプールの空きを確認する。ディスクは縮小しない。

```bash
cd ~/dotfile_infra
tofu plan -out=secretary-tools.plan
tofu show secretary-tools.plan
# secretary-dev以外の予期しない変更や、既存instanceの置換・削除がないことを確認する
tofu apply secretary-tools.plan
incus start secretary-dev   # 停止している場合だけ。既に稼働中なら不要
systemd-inhibit --what=sleep --mode=block --why="Secretary tools setup" ./provision/run secretary-dev
```

`nesting` を変更した場合は、provisionの前に作業中ジョブがないことを確認し、
`incus restart secretary-dev` でコンテナを再起動する。設定値が `true` でも、
再起動前はbubblewrapの `/proc` マウントに失敗する場合がある。
GPU追加後にデバイスが見えない場合も再起動する。
provisionはサーバーのSSHエージェントでKarakeep-toolを取得し、固定ソースをGit bundleでコンテナへ渡す。
コンテナ内にGitHubの秘密鍵や常設トークンを保存しない。

長い翻訳・教材変換も既存のCPU/GPU活動判定でスリープを抑止できるよう、サーバー側の判定対象を追加している。
こちらも適用する。

```bash
cd ~/dotfiles_server
sudo ./server/install-suspend.sh
```

導入中に不足・競合で失敗した場合は原因を解消してprovisionを再実行する。
ローカル設定や既存スキルの変更前コピーは `/var/backups/secretary/` に保存する。
Karakeep-toolの追跡ファイルに変更があれば、自動破棄せず停止する。

## Macのデータを手動転送

元データは削除しない。コードはGit経由で取得し、この作業ではGit無視対象のローカルデータだけを転送する。
`.env`・秘密情報・仮想環境・ネストしたリポジトリのコードは除外する。

Macで実行（Python 3.9以上）。出力先は新しい非公開ディレクトリにする。
ハッシュ計算は全データを読むため、43GB以上では時間がかかる。

```bash
python3 scripts/secretary-data-manifest "$HOME/home/Karakeep-tool" /private/tmp/secretary-transfer
ssh dev-server 'umask 077; mkdir -p ~/secretary-import/data'
caffeinate -i rsync -rt --partial --inplace --from0 --files-from=/private/tmp/secretary-transfer/files.nul \
  "$HOME/home/Karakeep-tool/" dev-server:secretary-import/data/
rsync -t /private/tmp/secretary-transfer/manifest.json /private/tmp/secretary-transfer/files.nul \
  dev-server:secretary-import/
```

必要なら最初のrsyncに `--dry-run` を加えて対象を確認する。
チェックサム作成後は転送完了までMac側の対象ファイルを変更しない。
`caffeinate` は転送中のMacのアイドルスリープを抑止する。途中で切断された場合は
同じコマンドを再実行し、非公開staging内の部分ファイルを再利用する。
大容量転送の前にMacのWi-Fi帯域・リンク速度を確認し、5GHzまたは有線LANを利用する。
2026-11-06の実機では2.4GHz接続が28Mbpsで、5GHzへ変更後もSSH単体は約6〜8MB/秒だった。
リンク速度の表示だけで実効速度を判断せず、通信経路も確認する。

サーバーで実行:

```bash
cd ~/dotfile_infra
systemd-inhibit --what=sleep --mode=block --why="Secretary data import" \
  ./secretary/import-data "$HOME/secretary-import"
```

インポートはファイルごとにSHA-256を検証し、新規ファイルだけを配置する。
同じ内容なら再開可能。既存ファイルと内容が違えば停止し、既存データを維持する。
転送元と転送先の両方を検証してからstagingの削除を判断する。Macの原本は残す。

既存のKarakeep認証は導入時に管理者用 `/etc/secretary-karakeep.json` へ移行する。`~secretary/.config/secretary/connections.json` とツールの `.env` には制限付きgatewayのトークンだけを保存する。
Macの `.env` はそのままコピーしない。接続を新規設定・変更した場合はprovisionを再実行する。
外部AIツールが必要なら `~secretary/.config/secretary/tool-secrets.json` に
`OPENAI_API_KEY` / `GEMINI_API_KEY` を設定し、secretary所有・mode 600にする。Gitや会話にキーを入れない。
辞書原本・NAS資料・ネストしたrepoのデータが自動選択に入らない場合は個別に確認する。

## 利用と承認

Macでは従来どおり `dev secretary` を使う。例えば:

- 「この文書をPLaMoで英訳して、新しいファイルに保存して」
- 「KarakeepからGPUの記事を探して」
- 「このdict.cc原本をStarDictに変換して」
- 「保存した記事をEPUBにして」「教材のOCR変換を計画して」

翻訳は文書領域内の入力から新しいファイルを作る。既存ファイルは上書きしない。
モデルは毎回ロードし、翻訳プロセスの終了時にVRAMを解放する。初回起動・長文には時間がかかる。
原文10万文字まで、トークン数に応じて分割。要求内で順次実行し、並列翻訳は拒否する。
PLaMoとOCRを同時にGPU実行しない。他コンテナともVRAMを共有する。

参照、一覧、状態照会、ローカル翻訳、専用辞書変換は通常のaskモードで追加承認を求めない。
汎用ツール実行は各クライアントの権限設定に従う。Karakeepの登録・タグ整理は別ツール、削除・一括更新は管理者が固定計画を確認して実行する。シェル全体は無条件許可しない。
既存のstrict設定・ユーザーのルールは維持するため、それらがある場合は追加承認が残る。
汎用実行は外部通信可能として扱い、私用データ取得後の通信判定も維持する。

ジョブの待機・再確認は `secretary_tools__job_status` の `wait_seconds=45` を使う。
最大45秒待って状態を返すので、queued/runningなら同じツールで再確認する。
待機専用の `shell: sleep ...` や汎用Pythonは使わない。shell全体の常時確認設定は維持する。
2026-11-06に追加129スキルとNanoMuse同梱11スキル（有効140件）を確認し、
追加スキルと生成テンプレートの待機指示を統一した。同梱11件にshell sleepの指示はなかった。
KarakeepのCLI例は引数の参考用で、操作は専用MCPを使い、APIキーを要求しない。

なろう取得の進捗は `secretary_tools__narou_status` を引数なしで呼ぶ。
MCP側で固定の `data/novels` を読み、候補数・EPUB数・途中TXTの保存話数・バッチ記録・
コンテナ内の取得プロセスを返す。shell/filesのworkspace制限を広げる必要はない。
進捗確認のためにcollect/downloadを再実行しない。TXTの行数は話数ではない。
この確認はネットワーク通信・ダウンローダー起動・ファイル変更を行わない。

医学書・学習教材EPUBの進捗は `secretary_tools__study_status` を使う。
`scope=medical|nonmedical|all` で保存計画のタスクを分類し、現在のプロファイルの
完了・停止・未着手、停止位置、配置済み出力、現在の空き容量を確認する。
元カタログの冊数・グループ数と変換タスク数は異なる。完了分は未校閲の下書きである。
GPUは `secretary_tools__gpu_diagnostics` で実際のOCR用Pythonを検査する。
固定された小さなCUDA計算だけを行い、OCR・変換・モデルのダウンロードは開始しない。
隔離shellにデバイスがないことを、MCP側にもGPUがない根拠にしない。
変換プログラムの既定deviceはCPU。GPU実行指定は `--device cuda` と
`--yomitoku-python /opt/secretary-ocr/bin/python`。実OCRの検証は別工程である。
移行済み記録にはMac絶対パスとパス由来のジョブIDが残るため、再開前に整合が必要。
進捗確認だけの依頼でrunを再実行しない。

## EPUBをMacへダウンロード

EPUB作成後、`secretary_tools__export_epub` に完成ファイルの相対パスを渡す。
通常はKarakeep-toolからの相対パス。文書workspace内なら `source="documents"` を指定する。
保存先が分からない場合は `secretary_tools__list_epubs` でファイル名・保存先・
既知のなろう作品名・教材名から検索する。本文は一覧や会話へ返さない。

専用ツールはZIP/EPUBのmimetypeとCRCを検証し、原本を残したまま
文書workspaceの `downloads/epub-<一意なID>/` に新しいコピーを用意する。
コピー完了までファイルを非表示にし、既存ファイルは上書きしない。
対応上限は1ファイル1GiB、展開合計4GiB・10,000エントリ。空き1GiBも保つ。

NanoMuseでは新しいファイルがチャットの成果物カードに表示される。
カードを開き、右上のダウンロードボタンまたは「Download it」でMacへ保存する。
既存の認証付きファイル配信を使い、新しい公開ポートや共有URLは作らない。
Macの「ブック」アプリへの取り込みや自動インストールは行わない。
進捗確認だけの依頼では、ダウンロード用コピーを自動作成しない。

スキルは `/home/secretary/.nanomuse/skills/` へ導入し、NanoMuse本来の検出処理で検証する。
実行ジョブはjob IDで追跡し、失敗・中断・出力上限を成功扱いしない。

翻訳推論はローカルだが、NanoMuseの会話モデルはOllama Cloud。
ローカル完結したい場合は「本文を会話に読み込まずファイルへ保存して」と依頼する。
既に会話に貼り付けた本文や、会話へ読み込んだ結果はクラウドモデルに送られる。

## 機能ごとの前提・未検証事項

157スクリプトをcatalog化し、補助モジュール・テストを除いた126件に個別スキルがある。
一覧・引数・ソース・制約は `secretary_tools__catalog` / `inspect`、
管理用一覧は `dotfile_infra/secretary/tooling/catalog.json` を参照する。

- Swift/VisionはmacOS専用でDebianでは実行不可。対応スキルはMac側で行う処理として案内する。
- NAS/SDカードの実物、別repo、辞書原本、教材、ファームウェアのhost buildは別途必要。
- Mac絶対パス固定の旧バッチ `run_extra.sh` / `run_mirror2.sh`、SD配置の `finalize.py place` は自動実行しない。
- YomiTokuは専用venvを導入する。モデルは初回実行で取得し、教材用data領域に保存する。
- CJSのレイアウト点検はChromium/Playwrightを導入するが、対象の展開済みEPUBや別の描画実装は別途必要。
- Java・Streamlit等のUIは外部公開設定を追加しない。用途に応じてlocalhostへのSSH転送を用意する。
- Macのkt doctorは構文検査。実データ・実アカウント・GPU推論の成功を意味しない。

## 適用後の確認

```bash
# Mac
dev secretary doctor

# サーバー
incus exec secretary-dev -- nvidia-smi
incus exec secretary-dev -- runuser -u secretary -- python3 /opt/secretary/secretary-tools.py doctor
```

NanoMuseで短文翻訳 → 新規ファイルとjob完了 → `nvidia-smi` でVRAM解放を確認する。
Karakeepは少件数の検索、EPUBは単一記事、辞書は小さな入力で確認してから対象を広げる。
provisionを再実行し、モデル設定・履歴・文書・スキルが維持されることも確認する。

## DSHを併用する

サーバー更新・plan/apply・`./provision/run secretary-dev` の同じ手順でDSHも導入する。
DSHのビルドには12GiB以上、推奨16GiBが必要。secretaryユーザーへsudo権限は付けない。
DSHのsandboxに必要な `secretary.nesting = true` を適用し、必要ならジョブ終了後にコンテナを再起動する。

```bash
# Mac
dev secretary       # NanoMuse
dev secretary dsh   # DeepSeek Harness（127.0.0.1:3080へSSH転送）
```

DSHは `dsh-web.service` でsecretaryユーザーとして常駐する。新しい外部公開ポートは追加しない。
初回はDSHのWeb UIでOllama Cloud等の認証を設定する。NanoMuseのAPIキーはコピーしない。
共有されるものは文書、専用MCP、Karakeep-tool、129スキル。会話履歴とモデル認証は別管理。
DSH用スキルは `~secretary/.dsh/skills/` に置き、MCPツール名をDSH形式へ変換する。
既存DSHスキルを編集した場合は自動上書きせず、再導入を停止して整合を求める。
NanoMuseのSentinel承認はDSHへ引き継がれないため、DSHの権限設定と秘書用指示で運用する。
外部更新・削除は依頼の対象範囲を確認し、承認が不足する場合は会話で確認する。
DSHからのGPU処理も他の翻訳・OCR・動画処理とVRAMを共有する。
暗号化バックアップにはDSHの認証・プロファイル・会話履歴も含める。

コンテナ内の対話CLIは次を使う（標準入力・出力を維持できる端末から実行）。

```bash
sudo -H -u secretary /usr/local/bin/secretary-dsh
```

## CodexとDSHの共通設定

Codex CLIも同じsecretaryユーザーへ導入する。既に入っているCLIのバージョン・モデル・認証・承認設定は保持する。
DSHには他の開発コンテナと同じcheckout-localのCodexサブエージェントプラグインを導入する。
このプラグインはDSH固定版が依存する専用Codexネイティブペイロードを使い、グローバルCLIへフォールバックしない。
両者は同じsecretaryユーザーのネイティブ認証を利用するが、CLIのバージョンが必ず一致するとは限らない。
モデル・permissionModeはプラグイン既定値のままにし、他の開発コンテナと同じ扱いにする。

```bash
# Mac。サーバー更新・provision後に初回だけログインする
dev secretary setup codex
dev secretary codex
```

device code認証はアカウント側で有効化が必要な場合がある。
[OpenAI公式の認証手順](https://developers.openai.com/codex/auth/) を参照。
Macや他コンテナの認証ファイルは自動コピーしない。ログイン完了後、DSHからCodex委譲を試す。
CLI単体にも秘書用MCPと129スキルを追加し、既存の独自MCPと競合する場合は上書きせず停止する。
スキル原本とNanoMuse/DSH側の129スキルは維持し、Codex向けコピーを `~secretary/.agents/skills` に配置する。

| 項目 | 他の開発用コンテナとの比較（リポジトリ設定） |
|---|---|
| DSH本体 | 同じ `provision/versions.env` の固定コミット |
| Node要件・ビルド | 同じNode 22系・pnpm lockfileでビルド |
| モデル一覧・既定モデル | 同じ `web-defaults.yml`。Ollama Cloud / deepseek-v4.1-flash:1017 |
| 権限・sandbox | DSH標準設定。全権限や承認省略へ変更しない。bubblewrapのGPU wrapperも共通 |
| Codex委譲プラグイン | 同じcheckoutのlinkインストール。ネイティブ設定・認証を利用 |
| Claude委譲・Claude CLI | 秘書には追加していない |
| 実行ユーザー・作業場所 | 秘書はsecretary / `/srv/secretary/documents` |
| 追加MCP・スキル | 秘書の専用MCP・129スキルを上乗せ |
| 認証・履歴 | コンテナごとに独立。実際の既存設定は上書きしない |
| 起動UI | 秘書は `dev secretary dsh`。Zed/ACPは秘書導入の対象外 |

他コンテナで利用者が変更した稼働中設定との完全一致は未確認。
構成の共通部分を揃えるもので、既存の個別設定を強制上書きする処理は入れない。

## 起動時のセットアップ案内

`dev secretary` は連携設定に加え、CodexログインとDSHモデル認証の状態を表示し、未設定なら次を案内する。

```text
[dev] Codex: 未ログイン
[dev] Codexログイン を設定しますか? [y=今する / Enter=今回は進む / s=今後聞かない]
```

`y` はその場でdevice codeログイン、DSHの場合はモデル認証用のWeb UIを開く。
Codexログイン後は状態を再確認する。未完了でもNanoMuse等の起動は続ける。
非対話実行では状態だけを表示し、ログインや設定画面を勝手に追加起動しない。

- `dev secretary dsh`: DSHの設定状態とCodexログインを確認。DSH認証が未設定なら、これから開く画面で何を設定するか案内する。
- `dev secretary codex`: Codexのログイン状態を確認してからCLIを開く。
- `dev --login secretary`（または `dev --login secretary dsh` / `codex`）: 「今後聞かない」を無視して未設定項目を再案内する。
- `dev --no-login secretary`（または `dsh` / `codex`）: 設定確認・案内を省略する。
- `dev secretary setup codex` / `dev secretary setup dsh`: 個別の設定へ直接進む。

スキップ設定はMacの `~/.config/dev/skip-secretary/<SSH名>/` に保存する。
CodexはネイティブCLIのlogin statusだけを確認し、その出力は捨てる。
DSHは選択中のプロバイダーと保存された認証の対応を確認する。認証ファイルがあるだけで設定済みとはしない。
DSHの認証保存済みは接続成功やキーの有効性を保証しない。独自のJS式を含む設定等は「確認できません」と表示する。
キーや認証ファイル内容はMacへ返さず、未導入・未設定・確認不能を区別する。
未導入の場合はサーバーのprovision手順を表示し、起動コマンドからインストーラーを自動実行しない。

## Karakeepの削除・一括更新の承認

従来の `karakeep_write` は廃止した。旧ツールの「常に許可」は新しい操作へ引き継がない。
NanoMuseの旧許可レコードだけをバックアップ後に除去し、他のツールの許可は維持する。

| 操作 | 専用ツールと許可の範囲 |
|---|---|
| 検索・取得 | `karakeep_read`。参照専用の接続を使う |
| URL/ノートを1件登録 | `karakeep_create`。既存記事の更新・削除は不可 |
| 1件の記事のタグ整理 | `karakeep_tags`。記事本体の削除は不可 |
| 記事の削除 | `karakeep_delete_plan`。対象ID・件数を固定した計画だけを作る |
| タイトル・ノート・アーカイブ等の更新、一括操作 | `karakeep_batch_plan`。変更内容と対象を固定した計画だけを作る |
| 計画の状態確認 | `karakeep_plan_status`。実行はしない |

登録・タグ整理はそれぞれ独立した許可対象にする。削除・一括更新は、会話で「はい」と答えるだけでは実行されない。
返された計画IDと対象・件数・変更内容を確認し、Macのターミナルで次を実行する。

```bash
dev secretary approve <32文字の計画ID>
```

管理者側で対象記事のID・タイトル・URL、操作の全内容、件数を表示する。
表示された `APPLY <操作数> <内容ハッシュの先頭8文字>` を入力した場合だけ、その固定内容を実行する。
このコマンドはAIユーザーのsecretaryでは実行できない。NanoMuse/DSH/Codexの継続許可にも依存しない。

計画は1..100操作、1時間有効。同時承認と再実行を拒否する。確認中に期限が切れた場合も実行しない。
途中失敗・タイムアウト・プロセス中断時は自動再試行しない。状態と実際の記事を確認して新しい計画を作る。
完了した操作数は記録するが、通信障害では最後の操作が成功したか断定できない場合がある。

### 汎用スクリプトからの迂回防止

実際のKarakeepキーは別の `secretary-karakeep` サービスユーザーだけが読める管理者ファイルへ移す。
AI側の `.env` とCLI環境には、`127.0.0.1:8766` の制限付きgateway用トークンを渡す。
このgatewayは生の更新API、削除API、承認・実行APIを受け付けない。GET/tRPC参照、1件登録、1件のタグ整理、計画作成・参照だけを公開する。
そのため、`run` を常に許可しても、渡された接続から直接Karakeepの記事を削除できない。

従来のNAS同期・再クロール・リスト同期は、そのまま書込適用できるとは案内しない。
NAS同期・再クロールは `--dry-run`、リスト管理は `status` / `show-list` のみ許可し、通常の書込実行は明示的に拒否する。
ファイルアップロード・再クロール・リスト同期の計画実行は今回の対象外で、追加の専用実装が必要。
通常の記事検索、記事のEPUB化、ローカル翻訳、辞書変換は維持する。

この制約は配布する接続に対するもの。他の場所に保存した古いフル権限キーや別のMCP接続は制御できないため、旧キーのコピーがある場合はKarakeep側で失効・再発行する。

### 導入・移行

両リポジトリをpullした後、これまでと同じ `./provision/run secretary-dev` を実行する。
移行時はNanoMuse/DSHを停止し、元の接続設定と.envを `/var/backups/secretary/karakeep-scope-*/` へ管理者だけが読める形で退避する。
旧キーをAI用設定から取り除き、gatewayを起動してから各AIサービスを起動する。
移行に失敗した場合は、未解決の認証ファイル等を整合するまでサービスを起動しない。

新規・変更時の設定コマンドは従来どおり。

```bash
dev secretary setup karakeep
```

APIキーは管理者用設定へ保存し、gatewayとNanoMuse/DSHを再起動する。Codexの既存チャットは必要に応じて開き直す。
暗号化バックアップには管理者用キーと計画の状態も含める。これらをAIユーザーが読める場所へ復元しない。
サーバー停止中のため、実アカウントの登録・タグ整理と、少件数の削除計画の実機検証は適用後に行う。
