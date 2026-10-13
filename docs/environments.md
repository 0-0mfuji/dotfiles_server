# 開発環境 (Incusコンテナ) の作成

`dev <target>` で開く先のコンテナは、別リポジトリ
[dotfile_infra](https://github.com/0-0mfuji/dotfile_infra) の OpenTofu (Terraform互換) で作る。
サーバー上で実行する (Macには何も入れない)。

## 目次

- [作り方](#作り方)
- [コンテナの中身を整える (provision)](#コンテナの中身を整える-provision)
- [スマホ用の設定 (Tailnet)](#スマホ用の設定-tailnet)
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
| DeepSeek Harnessの既定設定 | Ollama Cloudのモデル一覧と既定モデル (`deepSeek-v4.1-flash`) など。`provision/files/web-defaults.yml` から、**無い項目だけ**足す (上書きしない)。**APIキーは含まない** |
| 日本語の指示 | `~/.claude/CLAUDE.md` (Claude Code)、`~/.codex/AGENTS.md` (Codex)、`~/.dsh/AGENTS.md` (DeepSeek Harness)。既にあれば上書きしない |

**初回のビルドには、8GiB以上のメモリが要る** (4GiBではOOMで失敗する)。足りないコンテナは、`terraform.tfvars` の
`memory` を上げてから流す。スクリプトは、ビルドの前に確認して、足りなければ止まる。

**DeepSeek Harnessの既定設定**は、`os-dev` の設定を元にしている。`os-dev` でモデルを足したり変えたりしたら、
サーバーで取り込み直して、コミットする (既定モデルは、テンプレート側で管理するので取り込まない)。

```sh
./provision/capture-web-defaults     # os-dev の Web設定 -> provision/files/web-defaults.yml
git diff provision/files/web-defaults.yml
```

新しいコンテナで必要な操作は、**Web UIでのOllama CloudのAPIキーの入力**と、Claude Code / Codex の
ログインだけ (どちらもコンテナごと)。

バージョンを変えるときは `provision/versions.env` を編集して、`./provision/run` を再実行する。
DeepSeek Harness は開発者プレビューで、互換性が壊れる変更がある。コミットは意図して更新すること。

`git` / `jj` の既定の名前とメールは、**サーバーの** `~/.config/dev/provision.env` に書くと、
`./provision/run` が、全コンテナに反映する (Gitに入れない)。

```sh
GIT_USER_NAME="Your Name"
GIT_USER_EMAIL="you@example.com"
```

コンテナごとに変えたいときは、そのコンテナ内の `~/.config/dev/provision.env` に同じ名前で書く
(コンテナ内の値が優先される)。

## スマホ用の設定 (Tailnet)

スマホから、各コンテナのWeb UIを、**Tailnet内だけ**で開けるようにする。HTTPS証明書も
`tailscale serve` も使わない (Tailnet内の通信は、Tailscaleが暗号化している)。

```
スマホ → Tailnet (WireGuardで暗号化) → サーバーのTailscale IP:ポート (Incus proxy) → コンテナ内 127.0.0.1:3080
```

- コンテナ内のWeb UIは `127.0.0.1` のままなので、Macのトンネルの経路は変わらない。
- 待ち受けは**サーバーのTailscale IPだけ**。LAN (192.168.1.x) からは届かない。
- URLは `http://` になる (ブラウザの「保護された通信」ではないが、経路はTailscaleで暗号化済み)。

設定 (サーバー上、1回だけ):

1. サーバーのTailscale IPを調べる: `tailscale ip -4`
2. `terraform.tfvars` に、IPと、コンテナごとのポートを書いて `tofu apply` (Git管理外)。

   ```hcl
   mobile_bind_ip = "100.x.y.z"
   dev_instances = {
     os = { ip = "10.10.0.13", web_port = 8013 }
   }
   ```

3. `~/.config/dev/provision.env` を作る (Git管理外)。

   ```sh
   MOBILE_HOST=dev-server.<tailnet>.ts.net          # MagicDNS名 (tailscale status で確認)
   MOBILE_MAP="os-dev:8013 lang-dev:8011 cpu-dev:8012"   # コンテナ:ポート (web_port と同じ値)
   ```

4. `./provision/run` で、コンテナのWeb UIに、このホスト名とポートを許可させる。
5. スマホにTailscaleを入れ、同じTailnetに参加させる。`dev --mobile os` のQRを、カメラで読み取る。

`host/steps/40-incus.sh` が、IncusをTailscaleより後に起動する設定を入れる (起動時に、Tailscale IPへの
待ち受けが失敗しないため)。

**Tailscale Funnel (インターネット公開) は使わない。** DeepSeek Harness は、コマンドを実行でき、
セキュリティ監査も未実施のため、Tailnet内 + トークンの2段に限る。必要なら、TailscaleのACLで、
スマホからこのポートへの接続だけに絞れる。

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
