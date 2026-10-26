# monosite のWeb開発環境

`git@github.com:0-0mfuji/monosite.git` を `web-dev:~/src/monosite` で開発する。
Macの作業コピーではなく、GitHubからcloneした内容を使う。Macの未コミット変更は自動では転送しない。

```sh
dev web monosite                 # Zed + エージェントWeb UI + Zola
dev --preview web monosite       # Zolaだけ (通常 http://127.0.0.1:1111/)
```

`dev web` は igakutteru / monosite の選択になる。Vite (:5173)、Storybook (:6006) とポートは重ならない。
Zolaはループバックで待ち受け、既存のSSHトンネルでMacに公開する。

## ツールとライブラリ

| 用途 | 依存 | 配置・扱い |
| --- | --- | --- |
| サイト生成 | Zola 0.23.6 | `dotfile_infra/provision` で版と公式SHA-256を固定。Rustビルド環境は不要 |
| 多言語検索 | `pagefind[extended]==1.5.2` | monosite専用 `.venv`。ビルドしたHTMLから検索データを生成 |
| 翻訳 | `ollama==0.6.3` | 同じ `.venv` のPythonクライアント。Ollamaサーバーとgemma2は別途必要 |
| 数式 | KaTeX 0.16.9 | テンプレートからCDNを読み込む |
| 日本語改行・フォント | BudouX / Google Fonts | テンプレートから外部配信を読み込む |
| コメント・アクセス解析 | Bluesky / GoatCounter | ブラウザから外部サービスへ接続 |

Node / Python / uv は既存の web-dev のものを使う。monositeには package.json がなく、
`pnpm install` は不要。ブラウザがCDNに接続できないと数式・フォントなどは確認できない。
BudouXのCDN URLはプロジェクト側で版が固定されていない。

## 再構築

Zolaのインストールは別リポジトリの `dotfile_infra/provision/agents.sh` の `install_zola` が担当する。
更新した `provision/versions.env` と合わせ、通常のサーバー側手順 `./provision/run web-dev` で再現できる。

```sh
# Mac: 未配置なら既存のエージェント転送経由でclone
dev --zed web monosite

# 以下はweb-devで実行
cd ~/src/monosite
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python 'ollama==0.6.3' 'pagefind[extended]==1.5.2'
```

仮想環境は既存の `.gitignore` の対象。システムPythonやigakutteruの `.venv` には入れない。
プロジェクトには依存lockfileがないため、上記は直接依存の版のみ固定する。
間接依存まで同一に保存する場合は `uv pip freeze --python .venv/bin/python` の結果を別途管理する。

## 検索を含めたプレビュー

[Pagefind](https://pagefind.app/docs/) は生成後のHTMLを索引化する。
`zola serve` だけでは `/pagefind/pagefind.js` が作られない。

1. Macで `dev --preview web monosite` を実行する。
2. web-devで以下を実行し、検索を試す。

```sh
cd ~/src/monosite
.venv/bin/python -m pagefind --site public
```

プレビューは [Zolaの `--store-html`](https://www.getzola.org/documentation/getting-started/cli-usage/) を指定して、
検索対象のHTMLを `public/` に保存する。記事の変更後やプレビューの再起動後は、上の索引生成を再実行する。
Zolaの起動・ビルドは `public/` を再生成するので、索引生成はその後に行う。

本番相当のビルド確認:

```sh
cd ~/src/monosite
zola build
.venv/bin/python -m pagefind --site public
```

## 翻訳 (任意)

Pythonクライアントの導入だけでは翻訳は動かない。利用するOllamaサーバーに `gemma2` を用意し、
到達可能なURLを `OLLAMA_HOST` に設定する。既定はローカルの `http://localhost:11434`。
モデルの配置とサーバーの常駐化は、この登録では行っていない。

```sh
cd ~/src/monosite/translate
../.venv/bin/python translate.py
```

既存の `run.sh` は仮のvenvパス、`setting.sh` はシステムpipを使うため、上の専用環境から直接実行する。
翻訳は英語記事を上書きするので、実行後に `git diff` で確認する。

## 実機確認 (2026-10-24)

- web-devへSSHエージェント転送でclone済み。
- Zola 0.23.6を公式SHA-256照合後に導入。
- Python 3.12の専用venvにOllama 0.6.3 / Pagefind Extended 1.5.2を導入。
- `zola build` 成功。Pagefindがen / de / jaの3言語を索引化。`from ollama import Client` 成功。
- Zolaプレビュー起動とSSHトンネル経由のサイト・`/pagefind/pagefind.js` のHTTP 200を確認。
- Ollamaサーバーへの接続・翻訳実行、外部CDNやBluesky等のブラウザ動作は未検証。
