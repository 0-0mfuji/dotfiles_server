# 使い方 (`dev` コマンド)

```sh
dev os sota       # target "os" の中の、プロジェクト "sota" を開く (Zed、Web UI、QR)
dev os            # プロジェクトが複数あれば、番号で選ぶ (1つだけなら、そのまま開く)
dev lang          # プロジェクトを分けていない target は、そのまま指定する
dev secretary     # 秘書の未設定項目を案内し、NanoMuseを開く (Zedなし)
dev --zed os sota # Zed だけ
dev --web os      # Web UI (+ スマホ用のQR)
dev --preview video # 開発サーバー (Remotion Studio / Vite) だけ (projects.conf の preview列があるtarget。--studio も同じ)
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
- [1つのコンテナに複数のリポジトリを置く](#1つのコンテナに複数のリポジトリを置く)
- [ソースコードの置き場所](#ソースコードの置き場所)

## `dev` がすること

1. Development Serverに接続できなければ、Raspberry Pi経由でWake-on-LAN
2. SSHが通るまで待つ (`DEV_SERVER_WAIT_TIMEOUT` 秒、既定180)
3. `deps` があれば依存するコンテナを、続けて `instance` の停止中のIncusコンテナを起動 (依存先は止めない)
4. `repo` が設定されていて、コンテナ内に `path` が無ければ `git clone`
   (Macのsshエージェントを転送して認証する。privateでもOK。秘密鍵はコンテナに置かない)
5. Claude Code / Codex のログイン状況を表示する (未ログインでも**止まらない**。下記)
6. DeepSeek Harness の Web UI を開く (`--web` または指定なしのとき)
7. スマホ用のQRコードを表示する (`--mobile`、`--web`、または指定なしのとき)
8. `preview` が設定されていれば、開発サーバー (Remotion Studio / Vite) を開く (`--preview` または指定なしのとき。下記)
9. ZedのRemote Developmentで `path` を開く (`--zed` または指定なしのとき)

## 私用秘書 (`dev secretary`)

`secretary` は `projects.conf` のworkflow列を `secretary` にした専用target。
コンテナ名・SSH名は `secretary-dev`。Wake・起動・接続確認は共通処理を使い、
未設定の連携を案内してNanoMuseを開く。
Codex・Claude・GitHubログイン、Zed、DeepSeek Harnessの起動は行わない。
`--web` はNanoMuse、`--preview` はSilverBulletのみ。`--no-login` は案内を省略し、
`--login` は「今後聞かない」を無視して未設定項目を案内する。
`--zed` / `--mobile` はこのtargetでは未対応。
詳細は [secretary.md](secretary.md)。

## ログインの案内

`dev` は、コンテナ内の Claude Code・Codex・GitHub CLI (github.com) のログイン状況を、1行で表示する。

```
[dev] Claude Code: 未ログイン  Codex: ログイン済み  GitHub CLI: 未ログイン
```

ターミナルから実行していて、未ログインのものがあるときは、順に聞かれる。

| 入力 | 動作 |
| --- | --- |
| `y` | その場でログインを始める (`claude auth login` / `codex login --device-auth` / `gh auth login --hostname github.com`)。ブラウザのないコンテナでも使える方式 |
| Enter | 今回はログインせずに進む |
| `s` | 今後は聞かない (`~/.config/dev/skip-login/<ツール>` を作る) |

契約していない期間があっても、**ログインしなくても、そのまま先へ進む**。

| 設定 (`~/.config/dev/local.env`) | 効果 |
| --- | --- |
| `DEV_AGENT_CHECK=off` | 確認そのものを行わない (`dev --no-login` は今回だけ) |
| `DEV_SKIP_AGENTS="codex"` | 指定したツールだけ確認しない |

`DEV_SKIP_AGENTS="gh"` で GitHub CLI だけ案内を省ける。GitHub のログインを選ぶと、Mac で所有者 `0-0mfuji`、名前 `dev-container`、有効期限30日、Contents・Pull requests・Issues の Read and write を入力済みの Fine-grained PAT 作成画面を開く。組織へのアクセスを含めない個人開発用の設定:

- Resource owner: `0-0mfuji` を入力済み。作成前に自分の個人アカウントであることを確認する。
- Repository access: **ここだけ手動で `All repositories` を選ぶ** (個人所有の Private・Public)。公式のURLパラメータはこの選択に対応していない。対象を絞るなら `Only select repositories`。
- Expiration: 30日を入力済み。必要に応じて変更する。
- Repository permissions: コードの取得・push は `Contents: Read and write`、PR 操作は `Pull requests: Read and write`、Issue 操作は `Issues: Read and write`。必要な操作だけ付与する。workflow ファイルの更新には `Workflows: Read and write` も必要。

[GitHub公式のURLテンプレート仕様](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#pre-filling-fine-grained-personal-access-token-details-using-url-parameters) に従って事前入力する。組織やアカウントの権限は事前付与しない。GitHub上の公開リポジトリの読み取りは、Fine-grained PAT に常に含まれる。

続く `gh` の認証方法で **Paste an authentication token** を選び、生成したトークンを入力する。ブラウザでの OAuth 認証は選ばない。トークンは `gh` の入力欄だけに貼り付け、チャットや Git 管理ファイルには保存しない。認証情報は各コンテナで保持する。Fine-grained PAT の権限外の操作は失敗するので、その操作が必要なときに権限を見直す。

`dev` 起動時の `gh auth status` でトークンが無効になっていれば、期限切れ・失効時も再認証を案内する。`y` で作成画面を開き、新しいトークンを登録する。期限切れだけを判別するものではなく、認証確認の失敗をまとめて「未ログインまたは認証無効 (期限切れ等)」と表示する。常時監視やトークンの自動更新は行わない。`s` や `DEV_SKIP_AGENTS="gh"` で確認を省いている場合は案内されない。`s` を解除して案内するには `dev --login web` を使う (`DEV_SKIP_AGENTS`・`DEV_AGENT_CHECK=off` は別途解除)。

`gh` が未導入なら「未導入」と表示するので、サーバーの `dotfile_infra` で `./provision/run` を実行する (稼働中の全 `*-dev` が対象。停止中のものは起動後に実行)。

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

`git` と `jj` は、すべてのコンテナに入っている。`dev` の自動cloneは**常に `git clone`** で、
Macでの作業(gitのみ)にも影響しない。

**jjを使うリポジトリは、`projects.conf` の `vcs` 列に `jj` と書く。** `dev` が、clone後に、
次を自動で実行する (既にあれば何もしない)。

```sh
jj git init --colocate
```

`projects.conf` に無いリポジトリで、手動で使うときは、コンテナ内で同じコマンドを1回実行する。

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
# target    host      path            instance   repo                          vcs
os/sota     os-dev    ~/src/sota      os-dev     git@github.com:you/sota.git   jj
```

| 列 | 内容 |
| --- | --- |
| `target` | `dev <target>` の名前。複数のプロジェクトを置くときは `グループ/プロジェクト` (下記) |
| `host` | `~/.ssh/config.local` で定義したSSH Host名 |
| `path` | コンテナ内のプロジェクトパス |
| `instance` | Incusコンテナ名。`-` で無指定 |
| `repo` | GitHubのクローンURL。`-` で無指定 |
| `vcs` | `jj` で、clone後に jj を同居させる (下記)。省略または `git` は、gitのまま |
| `deps` | 依存するIncus instance (カンマ区切り)。`dev` が本体より先に起動する。`-` で無し |
| `preview` | 開発サーバー。`PORT` は Remotion Studio、`PORT=SCRIPT` は package.json のスクリプト (例 `5173=dev:web`)、`PORT=flutter` はFlutter Web。`-` で無し |
| `workflow` | 省略時は `development`。`secretary` は秘書用の設定案内・画面起動 |

### 依存コンテナ (`deps`)

`video` のように、別のコンテナ (`voice-dev` の VOICEVOX) を呼ぶ target は、`deps` に書く。

```
video     video-dev     ~/src/video      video-dev   -   git   voice-dev   3000
```

- 起動は `dev` の役目。**コンテナ同士は互いを知らない** (コンテナからホストの `incus` は呼べない)。
  呼び出し先のURLは、`video` 側の環境変数 (例: `VOICE_URL=http://<voice-devの固定IP>:50021`) で渡し、
  繋がらなければ、そのエラーを出して終わる。別のVOICEVOXに差し替えられる。
- 依存先は止めない (他のtargetと共有する)。サーバーが寝れば、全コンテナが止まる。
- 起動直後はAPIがまだ応答しないことがある。`RUNNING` になっただけでは、VOICEVOXの準備完了ではない。

### 開発サーバーのプレビュー (`preview`)

`dev` は、`preview` のポートで開発サーバーが動いていなければ、コンテナ内で起動し (ログは `~/.cache/preview-<PORT>.log`)、SSHトンネルでMacのブラウザに開く。

- npm系のプレビューには `package.json` と `node_modules` が必要。Flutterには `pubspec.yaml` と `web/` が必要。依存はプロジェクト側で導入する。
- トンネルはSSH接続なので、開いている間は自動Suspendを止める。既定で4時間後に閉じる (`DEV_WEB_TUNNEL_TTL`)。
- ローカルポートは、リモートと同じ番号から空きを探す (`DEV_STUDIO_LOCAL_PORT` で開始番号を変えられる)。
- 起動のしかた: `PORT` だけなら `npx remotion studio --port=PORT --no-open` (動画)。`PORT=SCRIPT` なら `corepack pnpm run SCRIPT --host 127.0.0.1 --port PORT` (Vite など)。
- `PORT=flutter` は `flutter run -d web-server --web-hostname 127.0.0.1 --web-port PORT`。`pubspec.yaml` と `web/` が必要。
- 複数のプレビューはカンマ区切りで指定する。`5173=dev:web,6006=storybook` ならWebアプリとStorybookを両方開く。`dev --preview web igakutteru` でも両方が対象。
- 表示先は末尾の `@/PATH?QUERY` で指定できる。例: `5174=dev@/volume.html?preset=high`。省略時は `/` を開く。パス・クエリには空白やカンマを直接含めず、必要なら URL エンコードする。
- `PORT=storybook` はサーバー側でブラウザを開かないよう `--ci --no-open` も渡す。
- 例: `video ... 3000` (Remotion Studio)、`web/igakutteru ... 5173=dev:web,6006=storybook` (Vite + Storybook)、`flutter/harmonic ... 7357=flutter`。

1つのtargetに設定できる `repo` は1つ。複数ある場合は、次のとおり、行を足す。

## 1つのコンテナに複数のリポジトリを置く

Flutterコンテナの `harmonic` は `dev flutter harmonic` で開く。Flutterの登録が1件の間は
`dev flutter` でも同じプロジェクトを開く。初回は `~/src/harmonic` に自動cloneされる。

同じコンテナ (`host` / `instance`) を指す行を、**`グループ/プロジェクト`** という名前で足す。

```
# target    host      path            instance   repo                          vcs
os/sota     os-dev    ~/src/sota      os-dev     git@github.com:you/sota.git   jj
os/boot     os-dev    ~/src/boot      os-dev     git@github.com:you/boot.git   jj
```

```sh
dev os sota      # 指定したプロジェクトを開く
dev os boot
dev os           # 複数あるので、番号で選ぶメニューが出る (Enterで1番目)
```

- リポジトリごとに、別々のZedのウィンドウ、別々のHarnessのワークスペースになる。
- コンテナは共通なので、環境 (Node.js、`jj`、ログイン状態、Web UI) は共有される。
- `dev os` だけのときは、プロジェクトが1つならそのまま開く。複数でも、対話できない環境 (スクリプトなど)
  では、メニューを出さずに、先頭の行を開く。
- `--zed` / `--web` / `--mobile` は、そのまま組み合わせられる (`dev --zed os boot`)。
- グループにしない target (`lang` など) は、今までどおり `dev lang` で開く。

## ソースコードの置き場所

**ソースコードはすべてコンテナ内の `path` に置き、Macには置かない。** ZedのUIと入力だけが
Macで動き、ファイル・Git・ターミナル・ビルドはコンテナ内で動く。

コンテナを作り直すと中身は消える。重要な変更は必ずGitHubへpushする。

### 秘書（NanoMuse）

`dev secretary`でNanoMuseを開く。
Chatで会話し、Libraryで文書を確認する。`dev secretary notes` は同じ文書をSilverBulletで開く。
設定手順は[秘書の手順](secretary.md)を参照。旧Hermesの履歴・認証情報はroot専用領域へ退避し、旧起動経路は廃止した。

スマホのブラウザ用QR: `dev secretary mobile`。スマホのTailscaleを接続して読み取る。
QRは認証情報を含むので共有しない。
