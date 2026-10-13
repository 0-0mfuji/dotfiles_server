# 開発環境 (Incusコンテナ) の作成

`dev <target>` で開く先のコンテナは、別リポジトリ
[dotfile_infra](https://github.com/0-0mfuji/dotfile_infra) の OpenTofu (Terraform互換) で作る。
サーバー上で実行する (Macには何も入れない)。

## 目次

- [作り方](#作り方)
- [コンテナの中身を整える (provision)](#コンテナの中身を整える-provision)
- [コンテナを足す・変える](#コンテナを足す変える)
- [注意事項](#注意事項)

## 作り方

前提: [server.md](server.md) の「ホスト構築」が済んでいること。

```sh
# Development Server上で
git clone git@github.com:0-0mfuji/dotfile_infra.git
cd dotfile_infra

./install.sh                          # OpenTofu CLI (未導入の場合のみ)
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars              # 項目は dotfile_infra のREADME参照
tofu init
tofu plan                             # 作られるものを確認
tofu apply
```

`dev_instances` の key が `<key>-dev` というコンテナ名になる。

## コンテナの中身を整える (provision)

`tofu apply` で作った直後のコンテナには、基本パッケージしか入っていない。
AIエージェントと `jj` の環境は、`provision/run` が整える (サーバー上で実行)。

```sh
cd ~/dotfile_infra
./provision/run              # 稼働中の全 *-dev に流す
./provision/run os-dev       # 指定したコンテナだけ
```

何度流しても同じ結果になる (入っているものは飛ばす。初回のビルドだけ数分かかる)。入るもの:

| 項目 | 内容 |
| --- | --- |
| Node.js | 22系 (DeepSeek Harness の要件 22.19以上)。公式tarballをチェックサム検証して導入 |
| `git` / `jj` | `jj` は `provision/versions.env` でバージョンとSHA-256を固定 |
| Claude Code / Codex | ログイン用のCLI (ログイン情報は入れない) |
| DeepSeek Harness | `shiguredo` 版 (日本語UI)。**コミットを固定**してビルドし、`dsh-web.service` として常駐 |
| プラグイン | Claude Code / Codex のサブエージェント (本体と同じチェックアウトから `link:` で導入) |
| 日本語の指示 | `~/.claude/CLAUDE.md` と `~/.codex/AGENTS.md` (既にあれば上書きしない) |

バージョンを変えるときは `provision/versions.env` を編集して、`./provision/run` を再実行する。
DeepSeek Harness は開発者プレビューで、互換性が壊れる変更がある。コミットは意図して更新すること。

`git` / `jj` の既定の名前とメールは、コンテナ内の `~/.config/dev/provision.env` に書くと反映される
(Gitに入れない)。

```sh
GIT_USER_NAME="Your Name"
GIT_USER_EMAIL="you@example.com"
```

## コンテナを足す・変える

1. `terraform.tfvars` の `dev_instances` にエントリを足す (`ip` は他と重ならない固定IP)。
2. サーバーで `tofu apply`。
3. Macの `~/.ssh/config.local` に `Host <key>-dev` を足す (`HostName` は上の `ip`、`ProxyJump dev-server`)。
4. Macの [config/projects.conf](../config/projects.conf) にtargetの行を足す (`instance` 列は `<key>-dev`)。

## 注意事項

- cloud-initはコンテナの**初回起動時にしか実行されない**。`packages` などを変えても既存の
  コンテナには反映されない。反映するには作り直す:
  `tofu apply -replace='incus_instance.dev["os"]'`
- **作り直すとコンテナ内のデータ (ソースコード含む) は消える。** 先にGitHubへpushする。
- 作られる `dev` ユーザーはパスワードなしでsudoを使える (コンテナ内のみ。ログインは公開鍵のみ)。
