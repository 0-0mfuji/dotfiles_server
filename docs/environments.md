# 開発環境 (Incusコンテナ) の作成

`dev <target>` で開く先のコンテナは、別リポジトリ
[dotfile_infra](https://github.com/0-0mfuji/dotfile_infra) の OpenTofu (Terraform互換) で作る。
サーバー上で実行する (Macには何も入れない)。

## 目次

- [作り方](#作り方)
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
