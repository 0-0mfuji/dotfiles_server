# 使い方 (`dev` コマンド)

```sh
dev os            # Zed、Web UI、スマホ用のQRコードを出す
dev --zed os      # Zed だけ
dev --web os      # Web UI (+ スマホ用のQR)
dev --mobile os   # スマホ用のQRコードだけを表示する
dev --login os    # Claude Code / Codex のログインを案内する (「今後聞かない」も無視)
```

## 目次

- [`dev` がすること](#dev-がすること)
- [ログインの案内](#ログインの案内)
- [Web UI](#web-ui)
- [スマホから使う (QR)](#スマホから使う-qr)
- [jj (Jujutsu) を使う](#jj-jujutsu-を使う)
- [projects.conf](#projectsconf)
- [ソースコードの置き場所](#ソースコードの置き場所)

## `dev` がすること

1. Development Serverに接続できなければ、Raspberry Pi経由でWake-on-LAN
2. SSHが通るまで待つ (`DEV_SERVER_WAIT_TIMEOUT` 秒、既定180)
3. `instance` が設定されていれば、停止中のIncusコンテナを起動
4. `repo` が設定されていて、コンテナ内に `path` が無ければ `git clone`
   (Macのsshエージェントを転送して認証する。privateでもOK。秘密鍵はコンテナに置かない)
5. Claude Code / Codex のログイン状況を表示する (未ログインでも**止まらない**。下記)
6. DeepSeek Harness の Web UI を開く (`--web` または指定なしのとき)
7. スマホ用のQRコードを表示する (`--mobile`、`--web`、または指定なしのとき)
8. ZedのRemote Developmentで `path` を開く (`--zed` または指定なしのとき)

## ログインの案内

`dev` は、コンテナ内の Claude Code と Codex のログイン状況を、1行で表示する。

```
[dev] Claude Code: 未ログイン  Codex: ログイン済み
```

ターミナルから実行していて、未ログインのものがあるときは、順に聞かれる。

| 入力 | 動作 |
| --- | --- |
| `y` | その場でログインを始める (`claude auth login` / `codex login --device-auth`)。ブラウザのないコンテナでも使える方式 |
| Enter | 今回はログインせずに進む |
| `s` | 今後は聞かない (`~/.config/dev/skip-login/<ツール>` を作る) |

契約していない期間があっても、**ログインしなくても、そのまま先へ進む**。

| 設定 (`~/.config/dev/local.env`) | 効果 |
| --- | --- |
| `DEV_AGENT_CHECK=off` | 確認そのものを行わない (`dev --no-login` は今回だけ) |
| `DEV_SKIP_AGENTS="codex"` | 指定したツールだけ確認しない |

DeepSeek の APIキーは、Web UIの 設定 → モデル に入力する (初回に案内が出る)。

## Web UI

コンテナ内で `dsh-web.service` が `127.0.0.1:3080` に常駐している (`dotfile_infra/provision` が導入)。
`dev` は、MacからSSHトンネルを張って、トークン付きURLをブラウザで開く。

- 同じコンテナへのトンネルが生きていれば、再利用する。ローカルポートは3080から空きを探す。
- **トンネルはSSH接続なので、開いている間はサーバーの自動Suspendを止める。** 既定で4時間後に自動で
  閉じる (`DEV_WEB_TUNNEL_TTL` 秒で変更)。
- URLのトークンは、サービスの起動のたびに変わる。

## スマホから使う (QR)

スマホには、Tailscaleを入れて、同じTailnetに参加させておく。`dev` が表示するQRコードを、
スマホのカメラで読み取ると、トークン付きのURLでWeb UIが開く。

```sh
dev --mobile os     # QRだけを表示する (Zedもブラウザも開かない)
```

- **カメラで読み取った直後に、認証画面 (`dsh web authentication required`) が出ることがある。**
  ブラウザの外 (カメラアプリ) から開くと、Harnessの認証クッキー (`SameSite=Strict` 固定) が、
  リダイレクト先に付かないため。**ページを再読み込みするか、URLをコピーしてブラウザに貼り付ける**と開く
  (クッキー自体は保存されている)。設定では変えられない。
- URLは**Tailnet内だけ**で有効 (インターネットにもLANにも公開しない)。トークンは、サービスの再起動のたびに変わる。
- QRの描画は、コンテナ側の `qrencode` で行う (Macには何も入れない)。
- 設定が無いコンテナでは、`dev os` では何も表示せず、`--mobile` のときだけ理由を表示する。
- サーバーが寝ているときは、`dev` がWake-on-LANで起こしてから表示する。スマホ単独では起こせない。
- **ブラウザの接続は、サーバーの自動Suspendを止めない** (SSH接続ではないため)。エージェントが作業中
  (CPUを使っている間) は起きているが、ただ画面を開いているだけでは、60分で寝る。

設定のしかた (1回だけ) は [environments.md](environments.md#スマホ用の設定-tailnet) を参照。

## jj (Jujutsu) を使う

`git` と `jj` は、すべてのコンテナに入っている。`dev` の自動cloneは**今までどおり `git clone`** で、
Macでの作業(gitのみ)にも影響しない。

コンテナ内で、`jj` を使いたいリポジトリのときだけ、次を1回実行する。

```sh
jj git init --colocate     # 既存のgitリポジトリの中に、jjを同居させる
```

- `.git` は今までどおり残る。`git` コマンド、Zed、Claude Code、Codex、`gh` は、そのまま動く。
- 追加される `.jj/` は、中身が `/*` で自動的にgitの対象外になるため、リポジトリの内容は変わらない。
- GitHubのリモートも共通なので、Macからはgitで普通に見える。
- 注意: jjを同居させると、`git status` が「detached HEAD」と表示される。これはjjの仕様
  (作業中の変更が、常にコミットとして扱われる)。ブランチ操作は `jj bookmark` を使う。

## projects.conf

[config/projects.conf](../config/projects.conf) を編集する。1行が1つのtarget。

```
# target  host      path            instance   repo
os        os-dev    ~/src/os        os-dev     git@github.com:you/my-os.git
```

| 列 | 内容 |
| --- | --- |
| `target` | `dev <target>` の名前 |
| `host` | `~/.ssh/config.local` で定義したSSH Host名 |
| `path` | コンテナ内のプロジェクトパス |
| `instance` | Incusコンテナ名。`-` で無指定 |
| `repo` | GitHubのクローンURL。`-` で無指定 |

1つのtargetに設定できる `repo` は1つ。複数ある場合は、別のtargetとして行を足す。

## ソースコードの置き場所

**ソースコードはすべてコンテナ内の `path` に置き、Macには置かない。** ZedのUIと入力だけが
Macで動き、ファイル・Git・ターミナル・ビルドはコンテナ内で動く。

コンテナを作り直すと中身は消える。重要な変更は必ずGitHubへpushする。
