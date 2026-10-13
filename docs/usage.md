# 使い方 (`dev` コマンド)

```sh
dev os          # Zed と DeepSeek Harness の Web UI の両方を開く
dev --zed os    # Zed だけ
dev --web os    # Web UI だけ
dev --login os  # Claude Code / Codex のログインを案内する (「今後聞かない」も無視)
```

## 目次

- [`dev` がすること](#dev-がすること)
- [ログインの案内](#ログインの案内)
- [Web UI](#web-ui)
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
6. DeepSeek Harness の Web UI を開く (`--zed` のときは省略)
7. ZedのRemote Developmentで `path` を開く (`--web` のときは省略)

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
