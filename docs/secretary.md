# 私用秘書（NanoMuse + SilverBullet）

NanoMuseを標準の秘書にしています。Ollama CloudのAPI設定と会話履歴は移行前のものを維持します。
メール・Plane・Karakeep・TimeTreeには既存の読み取り専用MCPで接続します。
Web UIは英語/中国語、日本語UIの追加はまだ行っていません。AIの応答言語は日本語です。

## Macから使う

```bash
dev secretary                 # NanoMuseを開く
dev secretary setup model     # モデル設定画面へ
dev secretary notes           # SilverBulletを開く（任意）
dev secretary doctor          # 外部連携の接続診断
dev secretary status          # 起動せず状態を確認
```

Macでの入口は `dev` に統一しています。旧 `secretary` コマンド、`--nanomuse`、`--hermes` は廃止しました。
`--preview` はSilverBulletのみ。通常の起動でSilverBulletの設定は要求しません。
モデル変更はSettings → Connectionsで行い、Save → Testの順で確認します。
Ollama CloudはOther OpenAI-compatible endpoint、Base URL `https://ollama.com/v1` を指定します。
APIキーを入力するときはNo keyを外してください。
NanoMuse Cloudへのログイン・アカウント作成は不要です。

## スマホのブラウザで開く

スマホを同じTailnetのTailscaleへ接続し、Macで次を実行する。

```bash
dev secretary mobile   # スマホ用QR
```

表示されたQRをスマホのカメラで読み取る。認証トークンはURLのフラグメントに含め、
HTTPログやコマンド引数には含めない。QRは認証情報なので共有しない。
Macで通常の `dev secretary` を対話端末から開いた場合もQRを表示する。
スマホはMacのSSH転送を経由せず、サーバーのTailscale IPへ接続する。
サーバーがスリープ中は接続できない。Suspend方針は変更しない。

導入側は別リポジトリの `secretary.nanomuse_port = 8787` と `mobile_bind_ip` を設定し、
計画を確認してapply後にprovisionを実行する。Incus proxyはホストのTailscale IPだけで待ち受ける。
NanoMuse本体は従来どおりコンテナ内の127.0.0.1で認証必須。
接続先は自動でsecretaryユーザーのprivateな `~/.config/secretary/mobile-url` に保存する。

## 移行した保存先と動作

| 項目 | 保存先・動作 |
| --- | --- |
| 文書の正本 | `/srv/secretary/documents`。NanoMuse LibraryとSilverBulletで共有 |
| 旧試用フォルダ | `/srv/secretary/nanomuse-workspace` は上記への互換symlink |
| APIキー・会話履歴・Vault | `/home/secretary/.nanomuse`。既存設定を維持 |
| 外部サービス認証 | `/home/secretary/.config/secretary`。既存MCPを引き継ぐ |
| TimeTree認証 | 専用サービスユーザーのみが読める従来の保存先 |
| サービス | `secretary-nanomuse.service` を有効化。旧Hermes・gatewayサービスは廃止 |

旧文書と試用中の文書を統合し、衝突した場合はNanoMuse側の編集を採用します。
統合前の両フォルダと設定を `/var/backups/secretary/nanomuse-migration-*/` に保存します。
バックアップはrootのみが読めます。元のSilverBullet認証ファイルは維持します。
旧Hermesの履歴・認証情報と旧実行ファイルは、コンテナ内のroot専用
`/var/backups/secretary/retired-hermes-*` に退避します。旧サービスと起動コマンドは撤去します。
この退避先も暗号化バックアップの対象です。

コンテナ名は引き続き `secretary-dev` です。Macからlocalhost:8787へSSH転送し、
トークン認証付きで開きます。Suspend方針は変更していません。
接続が切れた場合は `dev secretary` を再実行します。

## 導入・更新

別リポジトリdotfile_infraで次を実行します。既存コンテナの初回作成は下記の定義を参照してください。

```bash
cd ~/dotfile_infra
systemd-inhibit --what=sleep --mode=block --why="Secretary setup" ./provision/run secretary-dev
```

既定の導入先はNanoMuseです。NanoMuse 1.0.7のcommitとアーカイブSHA-256を固定し、
専用venvにインストールします。APIキー・会話履歴は上書きしません。
`provision/run` が内部で秘書専用処理へ振り分けます。

NanoMuse Cloud必須ログイン、会話同期、Hub、遠隔操作、更新チェックは無効です。
Ollama Cloudへ会話を送るAPI通信は発生します。外部連携の認証設定は別途必要です。

## 1. コンテナとサービスの導入（Debianサーバー上）

定義と導入スクリプトは別リポジトリ `dotfile_infra/secretary.tf` と `secretary/`。
コンテナ名は既存の規則に合わせて **`secretary-dev`**。専用resourceで定義し、
`provision/run` からも専用provisionへ振り分けるため、開発用ツールは導入されない。
既存の `terraform.tfvars` に次を追加する。IP・ポートは環境に合わせ、Gitには入れない。

```hcl
secretary = {
  ip         = "<空いているIncusネットワーク内のIP>"
  cpu        = 2
  memory     = "4GiB"
  disk_size  = "30GiB"
  # notes_port = 8030  # 任意。mobile_bind_ipのTailnet IPだけにSilverBulletを公開
}
```

```bash
cd ~/dotfile_infra
tofu init
tofu plan                 # 既存の変更も含まれる。意図した変更だけか確認
tofu apply
systemd-inhibit --what=sleep --mode=block --why="Secretary provisioning" ./provision/run secretary-dev
```

NanoMuseのソースとSilverBullet 2.12.1の公式バイナリはSHA-256を固定。
SilverBulletはslim版に相当するRust単体バイナリを使用し、Runtime APIを無効化する。
再実行しても文書・認証情報を上書きしない。更新は `secretary/versions.env` を変更して再導入する。


ユーザーは分離する。

| ユーザー | 用途 |
| --- | --- |
| dev | SSH管理用。既存cloud-initのsudo権限を持つ |
| secretary | NanoMuse・メールOAuth・Plane/Karakeep。sudo権限なし |
| secretary-notes | SilverBullet。文書のみ読み書き可能 |
| secretary-timetree | TimeTree認証と取得処理。NanoMuseは認証ファイルを読めない |

同じsecretaryユーザーで動くNanoMuseから、そのユーザーのメール等の認証情報を完全には隠せない。
読み取り制限はコネクターで実施し、Google/Microsoft側でも読み取りscopeだけ要求する。
Plane/KarakeepのAPIキー自体はより強い権限を持つ場合がある。

## 3. 既存Plane・Karakeep

```bash
dev secretary setup plane       # APIの接続先URL、APIキー、workspace slug
dev secretary setup karakeep    # URLとAPIキー
dev secretary doctor
```

URLはWebのベース（例 `https://plane.example.com`）。`/api/v1` は付けない。
サブパスが必要な構成はベースURLに含める。API用の別ドメインがある場合はそちらを使う。
接続情報は `/home/secretary/.config/secretary/connections.json`（0600）に保存。
MCPは独自の小さな読み取り専用アダプター。Planeのプロジェクト・タスク一覧、
Karakeepの検索・資料詳細を提供する。ページ送りが必要な応答を全件取得と解釈しない。

Plane CloudのAPI URLは `https://api.plane.so`（Web画面のapp.plane.soとは異なる）。
PlaneのProfile Settings → Personal Access Tokensでキーを作成する。
KarakeepはSettings → API Keysで作成する。
`dev secretary setup plane` / `karakeep` の完了後、Mac側コマンドがNanoMuseを再起動し、MCPツール一覧を更新する。
サーバーで直接設定した場合は `sudo systemctl restart secretary-nanomuse` を実行する。
入力候補はprivateな `~/.config/secretary/connection-defaults.json` に配置できる。
このファイルだけでは連携を有効にせず、APIキーの登録を必要とする。

## 4. Gmail（Google OAuth）

1. Google Cloudでプロジェクトを用意し、Gmail APIを有効化する。
2. OAuth同意画面を設定する。テスト中は自分をテストユーザーに追加する。
3. OAuthクライアントを **デスクトップアプリ** として作成し、JSONをダウンロードする。
4. MacからコンテナへJSONをコピーし、secretaryだけが読めるようにする。

```bash
scp <ダウンロードしたJSON> secretary-dev:/tmp/secretary-google-client.json
ssh secretary-dev 'sudo install -o secretary -g secretary -m 600 /tmp/secretary-google-client.json /home/secretary/.config/secretary/google-client.json && rm /tmp/secretary-google-client.json'
```

5. `dev secretary` の案内でGmailを選ぶか、`dev secretary setup gmail` を実行する。
   これらの入口はOAuth callback用のSSHトンネルを自動で張る。
   コンテナへ直接SSHして設定する場合だけ、Macの別ターミナルで次を実行する。

```bash
ssh -N -L 8765:127.0.0.1:8765 secretary-dev
```

6. `dev secretary setup gmail` を実行し、JSONのパスに
   `/home/secretary/.config/secretary/google-client.json` を指定する。
   表示されたURLをMacのブラウザで開き、認可する。5分以内に完了する。

Gmail scopeは `gmail.readonly` のみ。テスト公開状態ではrefresh tokenが短期間で失効する
場合がある。認証切れは同じ手順で再認証する。認証に失敗しても既存設定は保持する。
送信・削除・既読化・添付取得は行わない。HTMLだけのメールはsnippetで確認する。

## 5. outlook.jp（Microsoft OAuth）

1. Microsoft EntraのApp registrationsでアプリを登録する。
2. **個人Microsoftアカウントを含む**アカウント種別を選ぶ。
3. Mobile and desktop applicationsのリダイレクトに
   `http://localhost:8765/callback` を登録する（Web/SPA型ではなく公開クライアント）。
4. Microsoft Graphの委任アクセス許可に `Mail.Read` を追加する。
5. `dev secretary` の案内でoutlookを選ぶか、`dev secretary setup outlook` を実行する。
   OAuth callback用のSSHトンネルは自動作成される。
6. Application (client) IDを入力し、表示URLをMacで開いてoutlook.jpで認可する。

公開クライアント＋PKCEを使い、client secretは不要。エンドポイントは個人用の
`consumers`。要求scopeは `Mail.Read` と `offline_access`。
Entraアプリ登録が利用できないアカウントでは、この方式の初期設定を完了できない。
Gmail/Outlookの設定後にNanoMuseを再起動し、`dev secretary doctor` で確認する。

## 6. TimeTree共有予定（非公式・読み取りのみ）

公式の一般開発者向けAPIは終了済み。次の処理はWebの非公開エンドポイントを使う。
ログイン方式の制限やTimeTree側の変更で動かなくなる可能性があり、動作保証はしない。
参考: ap311036/timetree-mcp のコミット `babdef83d0fd1eb7a8d6197cd86d206a6654d8e9`。
上流コードや書き込み機能をインストールせず、ログインとGETだけを実装している。

```bash
dev secretary setup timetree   # 最初はカレンダーIDを空欄にする
dev secretary timetree-calendars  # 有効なIDと名前だけを表示
dev secretary setup timetree   # 対象共有カレンダーIDを指定して再設定
```

設定済みの場合、起動中だけ30分間隔で取得。スリープから復帰しても過去分通知は保証しない。
一部のカレンダーだけが失敗しても、成功した分を更新する。失敗分は前回の予定を残し、
partial/staleと失敗したIDを明示する。全件失敗なら前回のキャッシュを保持する。エラーと取得時刻をNanoMuseに渡す。
通常予定は日本時間の日付範囲で取得。終日はTimeTreeのUTC日付・終了日包含を考慮。
**繰り返し予定は原データを別項目で返し、まだ展開しない。**
未解釈・上限による省略があれば明示するため、全件を確認せず空き時間を断定させない。

認証は `/var/lib/secretary-timetree/credentials.json`（secretary-timetreeのみ0600）。
予定キャッシュは同配下 `cache/`。NanoMuseにはこのキャッシュの読取権限だけを付ける。
認証はメール／パスワード方式のみ。SNSログインのみのアカウントは未対応。

## 7. 文書・通知・バックアップ

文書は `/srv/secretary/documents`。SilverBulletではファイルをそのまま表示する。
NanoMuseの初期指示は `~/.nanomuse/config.toml` のagent.instructionsに設定する。

```text
今日の予定とPlaneのタスクを調べて、daily/YYYY-MM-DD.md に日次レポートを作成して。
このメールの返信案を mail/ に保存して。送信はしないで。
Karakeepから旅行の資料を探して、plans/ にリンク付きの計画書を作って。
```

通知先はNanoMuseのChannelsで設定する。通知設定もNanoMuseの画面で行う。
**自動Suspend設定は変更しない。起動中のみ通知する。**

暗号化バックアップ（SilverBulletログイン設定後）:

```bash
ssh secretary-dev 'sudo /opt/secretary/backup <ageの公開recipient>'
# 表示された /var/backups/secretary/backup-....age を管理者として安全な保存先へ転送
```

実行中のサービスを一時停止し、文書・NanoMuseの状態・退避済みHermesデータ・OAuth認証・TimeTree認証・
SilverBulletログインをageで暗号化する。終了時に元々起動していたサービスだけ再開する。
復号鍵はコンテナに置かない。構築用コード・ダウンロード済みランタイムは対象外。
定期バックアップや外部転送は自動登録しない。

復元は**新規の専用コンテナ**で導入を済ませ、サービスとTimeTree timerを停止して行う。
暗号化ファイルを信頼するものと確認し、`age -d -i <鍵> <backup> | sudo tar -xpf - -C /`。
ユーザーUID/GIDが元環境と異なる場合は所有者を各ユーザーへ修正する。
最後にNanoMuseとログイン設定済みのサービスを起動し、
文書と認証を確認する。本番コンテナへ確認なしに復元してはならない。

## 検証状況と残る実機確認

2026-10-26にサーバーとMacへ適用済み。結果は [適用記録](secretary-deployment-2026-10-26.md)。
NanoMuseのOllama Cloud接続テスト、systemd定義、Linuxでの文書共有を確認した。外部アカウントの認証は初回設定で行う。

ローカルではBash構文、Pythonテスト、固定版SilverBulletの起動・API認証・ファイル反映を検証する。
OAuth認可、既存サービスのバージョン差、
TimeTreeの実アカウント、スマホ表示、暗号化バックアップからの復元は実機確認が必要。
認証情報はチャットへ送らず、上記の設定コマンドで入力する。

ローカル検証コマンド:

```bash
# dotfile_infra側
python3 -m unittest discover -s secretary/tests -v
bash -n secretary/install secretary/provision secretary/backup secretary/files/secretary
tofu fmt -check secretary.tf
tofu validate
```

Mac launcherの検証: `python3 -m unittest discover -s tests -v`。
対話での設定開始・スキップ・`--login`による再案内も擬似端末で検証する。

## 旧Hermesの保管データ

旧サービスの起動経路は廃止しました。履歴・認証情報はroot専用の
`/var/backups/secretary/retired-hermes-*` に保存します。必要なデータを取り出す場合も、
認証情報を文書フォルダへ置かないでください。過去の適用経緯は
[導入記録](secretary-deployment-2026-10-26.md)に残しています。
