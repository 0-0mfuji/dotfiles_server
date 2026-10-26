# 秘書環境の適用記録（2026-10-26）

このページは過去の適用記録です。旧Hermesと `secretary` 起動コマンドは廃止済みです。
現在の操作は [秘書の手順](secretary.md) の `dev secretary ...` を使ってください。

サーバーとMacへ適用済み。外部アカウントの認証情報は移植していない。
初回はMacのターミナルで `dev secretary` を実行し、案内から登録する。

## サーバー

- OpenTofuの保存済みplanを確認し、`incus_instance.secretary["main"]` だけを新規作成。
  結果は **1 added / 0 changed / 0 destroyed**。既存の開発環境は変更していない。
- コンテナは `secretary-dev`、2 CPU / 4 GiB / 30 GiB、GPUなし・非特権。
  IPは既存の定義・割当と重複しないものを選び、サーバーのGit管理外tfvarsに保存。
- Hermes v0.22.5（`bf0203a794a07aac3ff764972ab9087baa4e4f4e`）とSilverBullet 2.12.1を導入。
- `secretary-hermes.service` は自動起動・稼働中。127.0.0.1:9119でHTTP 200を確認。
- SilverBulletはログイン設定後に `secretary-notes.service` を起動する。
  本物のパスワードは自動生成・移植していない。
- gatewayとTimeTree timerは未有効化。各サービスの設定後に必要に応じて有効化する。
- AIユーザーのsudo不可、文書の共有書き込み権限、TimeTree領域への書き込み不可を確認。
- 適用後の秘書リソースのtargeted planは差分なし。
- ホストの自動Suspend設定は変更していない。導入中のみ `systemd-inhibit` を使用。

## Mac

- 既存の `dev` シンボリックリンクを維持し、互換用 `secretary` リンクを追加。
- `~/.ssh/config.local` に `secretary-dev` を追加。`dev-server`経由、User=dev、エージェント転送なし。
- 既存のローカル環境設定へ、未定義の `SECRETARY_*` 項目だけを追加。
- 変更前の設定は `~/.config/dev/secretary-rollout-backup/` に非公開で保存。
- 実際の `dev --web secretary` で設定状態表示、SSHトンネル作成、Hermesのブラウザ起動を確認。

## 検証

- Mac launcherの11テスト、秘書設定・連携処理の15テストを確認。
- systemdユニットのverify、Linux版SilverBulletの起動と認証・文書読取・別ユーザーの編集反映を確認。
  SilverBulletの検証は一時サービスと一時文書で行い、終了後に削除。
- 導入時のGit所有者チェックを、rootではなくsecretaryユーザーで実行するよう修正。
- upstreamが自動作成する未認証のprovider=autoを、設定済みと誤判定しないよう修正。
- upstreamの既存SOULを保持し、秘書用指示を一度だけ追加するよう修正。

## 初回に残る設定

`dev secretary` でOllama Cloud・SilverBulletログイン・Gmail・outlook.jp・Plane・Karakeep・
TimeTree・任意の通知先を案内する。GmailとOutlookにはOAuthクライアント登録が必要。
接続手順と制約は [secretary.md](secretary.md)。メール等の実データでの検証、
スマホからのアクセス、暗号化バックアップからの復元はまだ実施していない。
## NanoMuse並行試用の追加

- secretary-dev内にNanoMuse 1.0.7を追加。commitとソースアーカイブのSHA-256を固定・照合。
- `secretary-nanomuse.service` と `secretary-hermes.service` の同時activeを確認。
- localhost:8787のhealth APIはHTTP 200、auth=true。未認証のLibrary APIは401。
- 認証後のLibrary APIでコピーした文書と日本語ガイドを確認（初期3文書）。
- NanoMuse公式MCPクライアントで既存adapterのinitialize/list/call成功。
  接続先は未設定のため、公開ツールは現在 `secretary__timetree_snapshot` のみ。
  実際の共有予定取得成功を示すものではない。
- Macの `dev --no-login --nanomuse secretary` で起動処理・SSH転送・認証付きopen呼び出しを確認。
  WebのConnectフォームも描画を確認。トークンは端末ログへ表示しない。
- Launcherテスト15件、secretary unit test15件が成功。
- APIキー未入力のため、実際のAI応答とメール・Plane・Karakeep・TimeTree取得は未検証。
- UIは英語/中国語、AIの応答言語は日本語。自動Suspend方針は変更なし。
- 導入前のサーバー側スクリプトと導入ログは
  `~/.config/dev/secretary-rollout-backup/nanomuse-2026-10-26/` に保存。
- 暗号化backup対象にNanoMuseのstate/workspaceを追加。復元テストは未実施。

## NanoMuseを標準へ移行

- Macの `dev secretary` / `secretary` / `secretary chat` / `dev --web secretary` はNanoMuseのみを開く。
- サーバー側provisionも既定をNanoMuseへ変更。Hermesの導入は明示指定時のみ。
- Hermesと旧gatewayは停止・自動起動無効化。旧設定・履歴は保存。
- NanoMuseの設定・Vault・会話履歴を維持。モデルは `deepseek-v4.1-flash:1017`。
- 移行後のOllama Cloud Testは成功、応答OK（784ms）。
- 文書を `/srv/secretary/documents` へ統合。旧試用パスは互換symlink。
- 統合前の両文書フォルダとconfig.tomlはroot専用の
  `/var/backups/secretary/nanomuse-migration-47k7izr7/` に保存。
- 再実行で二重コピーが作られないこと、Libraryに3文書が出ることを確認。
- NanoMuse APIで検証用文書を作成し、SilverBulletユーザーが読めることを確認。確認後に削除。
- Launcher 17件、secretary/migration 18件、合計35件のテストが成功。
- Gmail/Outlook/Plane/Karakeep/TimeTreeの認証設定は引き続き未設定。
- 日本語UIの追加は未実施。Suspend方針も変更していない。

## TimeTree実アカウントの接続確認

- 認証とカレンダー一覧取得は成功。無効化済みカレンダー1件の予定取得がHTTP 400になっていた。
- 認証設定の控えを専用ユーザーのみ0600で保存し、無効化済みIDを同期対象から除外。
- 有効な5カレンダーから552件の予定データをキャッシュできた。stale=false、partial=false、errorなし。
- 起動中に30分間隔で取得するtimerを有効化。Suspend方針は維持。
- 一部失敗時も成功したカレンダーを更新し、失敗分は旧データと明示的なエラーを保持する処理を追加。
- `secretary timetree-calendars` で有効なカレンダーのIDと名前だけを表示できる。
- Pythonテスト23件、launcherテスト17件が成功。NanoMuseへキャッシュを反映済み。

## スマホブラウザ用QR

- secretary-devのIncus proxyを追加。待受はホストのTailscale IPv4だけ、接続先はコンテナ内127.0.0.1:8787。
- targeted planはsecretary-devの更新1件のみ。適用結果は0追加・1変更・0削除。
- 認証必須を維持。Tailnet用healthは200、未認証の文書一覧は401、Macから認証後の文書一覧は200。
- `secretary mobile` / `dev --mobile secretary` で端末にQRを表示できることを実機確認。
- 対話端末から通常の `dev secretary` を実行した場合もQRを表示する。
- トークンはURLフラグメントに含め、ログ・コマンド引数へは出さない。QRは認証情報として扱う。
- Python 25件・launcher 18件、合計43件のテスト成功。tofu fmt/validateも確認。
- Android実機からの読み取りはユーザー側の確認待ち。スマホでTailscale接続が必要。
- Suspend方針は変更なし。サーバー起動中のみ利用できる。
