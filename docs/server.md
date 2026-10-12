# Development Server (Debian)

Debian 13 (UEFI)。実際の開発処理はここのIncusコンテナで行う。

## 目次

- [構築の流れ](#構築の流れ)
- [このリポジトリのserver設定](#このリポジトリのserver設定)
- [自動Suspend](#自動suspend)

## 構築の流れ

1. **ホスト構築** (SSH/WoL/Tailscale/ZFS/Incus導入、ディスク初期化): `dotfile_infra` の
   [host/README.md](https://github.com/0-0mfuji/dotfile_infra/blob/main/host/README.md)
2. **Incus環境の作成** (コンテナ): [environments.md](environments.md)
3. **このリポジトリのserver設定**: 下記

## このリポジトリのserver設定

サーバー上で、一般ユーザーから実行する。

```sh
git clone git@github.com:0-0mfuji/dotfiles_server.git
cd dotfiles_server
./install.sh server
```

共通のshell設定とgit設定をリンクする。開発ツール自体は入れない
(ツールはコンテナ側で `dotfile_infra` が管理する)。

## 自動Suspend

アイドルが続いたら `systemctl suspend` する (S3)。条件は次の3つがすべて成り立つとき。

- 確立済みのSSHセッションが無い
- `systemd-inhibit` でsleepをブロックしているものが無い
- 最後にアクティブだった時から、`DEV_IDLE_TIMEOUT` 秒 (既定3600) 以上経った

`sudo` が必要なため、`./install.sh server` が表示するコマンドを手動で実行する。
詳細と、長時間ジョブからSuspendを止める方法は
[server/systemd/README.md](../server/systemd/README.md)。

> 外出先から起こすには、Raspberry Pi経由のWoLが必要。[raspi.md](raspi.md) を参照。
