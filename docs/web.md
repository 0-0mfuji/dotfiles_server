# Webアプリ開発環境 (web-dev: igakutteru)

`web-dev` は、Node + Python のWebアプリ開発用のコンテナ。最初のプロジェクトは
[igakutteru](https://github.com/0-0mfuji/igakutteru) (医師国家試験の問題検索サービス: React 19 + Vite / Hono on Cloudflare Workers /
Drizzle + Turso / Pythonのデータパイプライン)。**サーバーを作り直しても、この手順で再現できる。**

> 名前の `web` は、用途 (Webアプリ開発) の意味。`dev --web` (DeepSeek HarnessのWeb UI) とは別物。
> プロジェクトは `dev web igakutteru` のように、`グループ/プロジェクト` で開く ([usage.md](usage.md#1つのコンテナに複数のリポジトリを置く))。

## 目次

- [構成と、入れるもの](#構成と入れるもの)
- [ゼロから作る手順](#ゼロから作る手順)
- [動作確認](#動作確認)
- [日々の使い方](#日々の使い方)
- [うまくいかないとき](#うまくいかないとき)
- [実機での確認状況](#実機での確認状況)

## 構成と、入れるもの

コンテナ (`web-dev`、`provision/agents.sh` の `install_web`) には、**どのWebプロジェクトでも要る道具だけ**を入れる。
プロジェクト固有の依存は、プロジェクトの lockfile で入れる。

| 層 | 内容 | 管理するところ |
| --- | --- | --- |
| コンテナ | Node 22、corepack (pnpm)、`uv` + Python 3.12、`git-lfs`、`gh`、`zip` / `unzip`、`turso` (版とSHA-256を固定)、GPU (`libcuda1`) | `dotfile_infra/provision` |
| プロジェクト (JS) | pnpm 11.0.3 (`packageManager`)、React 19 / Vite 8 / Tailwind 4 / DuckDB-Wasm / Storybook / wrangler (devDependency) / Playwright | `pnpm-lock.yaml` |
| プロジェクト (Python) | `pipeline/requirements.txt` (duckdb、lindera-python、torch、transformers、spacy ほか) | `pipeline/.venv` |
| 秘密 | `.env`、`apps/worker/.dev.vars` | **Git管理外。手で置く** |
| 生成物 | `data/igakutteru.db` (gitignore) | `pipeline/build.py` で作るか、Macから持ち込む |

入れない / 使わないもの:

- **Ollama**: `llm_tagger.py` の `qwen3:14b` は、GPUのVRAM (8GB) に対して重い。OpenAI などのAPIプロバイダーを使う。
- **vllm**: `requirements.txt` でコメントアウトされている。

## ゼロから作る手順

前提: [server.md](server.md) のホスト構築と、[environments.md](environments.md) の `tofu apply` が済んでいること。

### 1. コンテナを作る (サーバー上)

`~/dotfile_infra/terraform.tfvars` の `dev_instances` に、`terraform.tfvars.example` の `web` を写す。

```hcl
web = {
  cpu       = 8
  memory    = "16GiB"       # Vite / torch / DeepSeek Harness のビルド (12GiB以上) 用
  disk_size = "150GiB"      # .git 2GB + data/ 14GB + node_modules + venv(torch)
  ip        = "10.10.0.30"  # 他と重ならない値に
  web_port  = 8015          # スマホ用 (DeepSeek HarnessのWeb UI)
}
```

```sh
cd ~/dotfile_infra && git pull
tofu plan        # 追加1・削除0 を確認
tofu apply
```

`~/.config/dev/provision.env` の `MOBILE_MAP` に `web-dev:8015` を足す。

### 2. 中身を整える (サーバー上)

```sh
./provision/run web-dev
```

初回は DeepSeek Harness のビルドがあり、数分かかる (16GiBの上限が要る)。ログに次が出る。

```
[provision] web: node v22.x / uv 0.13.1 / python 3.12.x / git-lfs x.y.z: ok
[provision] turso 1.0.34: installed
```

### 3. Mac: SSH

`~/.ssh/config.local` (Git管理外) に足す。

```
Host lang-dev cpu-dev os-dev video-dev web-dev     # 共通設定の行に web-dev を足す

Host web-dev
    HostName 10.10.0.30        # tfvars の web の ip
```

[config/projects.conf](../config/projects.conf) の `web/igakutteru` 行は、すでに入っている。

```
web/igakutteru  web-dev  ~/src/igakutteru  web-dev  git@github.com:0-0mfuji/igakutteru.git  git  -  5173=dev:web
```

- `vcs` は `git` のまま。igakutteru は `git worktree` (`.claude/worktrees`) を使うので、jj の colocate にしない。
- `preview` 列の `5173=dev:web` は、`pnpm run dev:web` (Vite) をコンテナ内で起動して、SSHトンネルでMacのブラウザに開く、の意味。

### 4. clone して、LFS を取る

```sh
dev --zed web igakutteru        # 自動clone (privateはMacのsshエージェントを転送)
# コンテナ内で
cd ~/src/igakutteru && git lfs pull      # data/ontology.duckdb (LFS)
```

### 5. 秘密を置く (Macから)

**Git管理外のファイル。リポジトリにも、チャットにも貼らない。**

```sh
scp ~/home/igakutteru/.env                 web-dev:~/src/igakutteru/.env
scp ~/home/igakutteru/apps/worker/.dev.vars web-dev:~/src/igakutteru/apps/worker/.dev.vars
```

`.dev.vars` の `WEB_ORIGIN` は、Viteのoriginと一致させる (既定 `http://localhost:5173`)。Macのブラウザから
トンネルで開くので、そのままでよい。

### 6. JS の依存と Playwright (コンテナ内)

```sh
cd ~/src/igakutteru
pnpm install --frozen-lockfile
pnpm --filter web exec playwright install --with-deps chromium     # テスト用。aptの依存も入る (sudo)
```

### 7. Python のパイプライン (コンテナ内)

```sh
cd ~/src/igakutteru/pipeline
uv venv --python 3.12 .venv
# torch は、ホストのドライバ550 (CUDA 12.x) に合わせて cu126 の索引から先に入れる (PyPIの既定は CUDA 13 で動かない)
uv pip install --python .venv/bin/python torch --index-url https://download.pytorch.org/whl/cu126
uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python -c "import duckdb, torch; print(duckdb.__version__, torch.cuda.is_available())"
```

リポジトリの README にある ipadic 辞書の取得と `web/public/ipadic.zip` の作成も、同じ手順で行う (初回のみ)。

### 8. データベースを用意する

`data/igakutteru.db` はgitignoreされている。どちらかで用意する。

```sh
# a) Macから持ち込む
rsync -av ~/home/igakutteru/data/igakutteru.db web-dev:~/src/igakutteru/data/
# b) コンテナで作る
cd ~/src/igakutteru/pipeline && .venv/bin/python3 build.py
```

### 9. 開発サーバーを起動する

```sh
dev web igakutteru        # Zed + Web UI + Vite (localhost:5173 がMacのブラウザで開く)
dev --preview web igakutteru    # Vite だけ
```

Worker (臨床ノートなどのサーバー同期) も使うときは、コンテナ内でルートから `pnpm dev` (`turso dev` + `wrangler dev`)。
Worker を起動せずに `/notes` を開くと `Failed to fetch` になる。

## 動作確認

サーバーでしか確認できない項目。上から順に。

| # | 確認 | 期待する結果 |
| --- | --- | --- |
| 1 | `./provision/run web-dev` | 終了コード0。`web: ... ok`、`turso ... installed` |
| 2 | コンテナ: `node -v; pnpm -v; uv --version; git lfs version; turso --version` | すべて版が出る (pnpm は `packageManager` の版を初回に取得) |
| 3 | `dev --zed web igakutteru` | `~/src/igakutteru` がcloneされ、Zedで開く |
| 4 | `git lfs pull` 後に `ls -lh data/ontology.duckdb` | 数百MB (LFSのポインタ=数百バイトではない) |
| 5 | `pnpm install --frozen-lockfile` | エラーなし |
| 6 | `pnpm --filter web test` / `pnpm --filter @igakutteru/worker test` | vitest が通る |
| 7 | `pnpm lint` (web) | エラーなし |
| 8 | `dev --preview web igakutteru` | Macの localhost:5173 が 200、画面が出る |
| 9 | `pipeline/.venv/bin/python3 -c "import torch; print(torch.cuda.is_available())"` | `True` |

## 日々の使い方

```sh
dev web igakutteru        # Zed + Web UI + Vite
dev --preview web igakutteru
```

- Viteのトンネルは、開いている間は自動Suspendを止める。4時間で閉じる (`DEV_WEB_TUNNEL_TTL`)。
- 長いビルド・torch の計算は、CPU / GPU の使用で自動Suspendを止める (GPUは使用率で検知)。
- GPU (VRAM 8GB) は、`video-dev` / `blender-dev` と分け合う。重い計算は、1つずつ。
- ブランチ運用とデプロイ (`staging` / `main`) は、igakutteru の `CLAUDE.md` / `DEPLOY.md` に従う。
  Cloudflare は `wrangler login` (ブラウザが要る) ではなく、環境変数 `CLOUDFLARE_API_TOKEN` を使う。

## うまくいかないとき

| 症状 | 確認 |
| --- | --- |
| provision が `web: apt install FAILED` | ログのパッケージ名。Debianの版で名前が違うことがある (`WEB_PKGS`) |
| provision が `turso: checksum FAILED` | `versions.env` の `TURSO_VERSION` と `TURSO_SHA256` |
| `provision` が DeepSeek Harness のビルドで落ちる (SIGKILL) | メモリ上限。12GiB以上 (推奨16GiB) |
| clone が失敗する | Macのsshエージェントに鍵があるか (`ssh-add -l`)。privateリポジトリは、エージェント転送で認証する |
| `data/ontology.duckdb` が数百バイト | `git lfs pull` を実行していない (`git lfs install` は provision 済み) |
| `pnpm` が見つからない / 版が違う | `corepack enable` 済みか。`packageManager` の版が、初回に取得される |
| Viteが開かない | コンテナの `~/.cache/preview-5173.log`。`node_modules` があるか。`--host 127.0.0.1` が効いているか |
| `/notes` で `Failed to fetch` | Worker が未起動。ルートで `pnpm dev`。`WEB_ORIGIN` とViteのoriginが一致しているか |
| `torch.cuda.is_available()` が False | `nvidia-smi` が通るか。torchが CUDA 13 のビルドになっていないか (cu126 の索引で入れ直す) |
| `playwright install --with-deps` が失敗 | Debian 13 のaptパッケージ名の違い。エラーに出る不足ライブラリを `apt install` する |
| `requirements.txt` が解決しない | Python 3.12 か。torch / spacy / transformers の組み合わせ。まず `requirements-control-plane.txt` だけ入れる |

## 実機での確認状況

**このコンテナは、書いてあるだけで、まだ実機で作っていない。** 最初の実行で確かめて、違えば該当の箇所を直し、ここを更新する。

- `install_web` の apt パッケージ名 (`git-lfs` `gh` `zip` `unzip`)、`turso` のtarball、`uv python install 3.12`。
- Vite が `--host 127.0.0.1 --port 5173` を、`pnpm run dev:web` 経由で受け取るか。
- Playwright の Chromium (`--with-deps`) が Debian 13 で入るか。
- `requirements.txt` が Python 3.12 + cu126 の torch で解決できるか。
