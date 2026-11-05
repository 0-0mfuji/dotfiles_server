# 私用秘書の翻訳・Karakeepツール導入

サーバー停止中に準備した変更。サーバー上のGPU推論と実アカウントでの動作は、起動後に確認する。
コードは `dotfile_infra` の `secretary/`、Mac側の転送準備はこのリポジトリの
`scripts/secretary-data-manifest` で管理する。

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

GPU追加後に見えない場合は、作業中ジョブがないことを確認してコンテナを再起動する。
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
rsync -rt --partial --from0 --files-from=/private/tmp/secretary-transfer/files.nul \
  "$HOME/home/Karakeep-tool/" dev-server:secretary-import/data/
rsync -t /private/tmp/secretary-transfer/manifest.json /private/tmp/secretary-transfer/files.nul \
  dev-server:secretary-import/
```

必要なら最初のrsyncに `--dry-run` を加えて対象を確認する。
チェックサム作成後は転送完了までMac側の対象ファイルを変更しない。

サーバーで実行:

```bash
cd ~/dotfile_infra
systemd-inhibit --what=sleep --mode=block --why="Secretary data import" \
  ./secretary/import-data "$HOME/secretary-import"
```

インポートはファイルごとにSHA-256を検証し、新規ファイルだけを配置する。
同じ内容なら再開可能。既存ファイルと内容が違えば停止し、既存データを維持する。
転送元と転送先の両方を検証してからstagingの削除を判断する。Macの原本は残す。

認証はコンテナの既存 `~secretary/.config/secretary/connections.json` を再利用し、必要な形式を導入時に生成する。
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
汎用ツール実行・CLI更新はツールの承認画面を通す。シェル全体は無条件許可しない。
既存のstrict設定・ユーザーのルールは維持するため、それらがある場合は追加承認が残る。
汎用実行は外部通信可能として扱い、私用データ取得後の通信判定も維持する。

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
