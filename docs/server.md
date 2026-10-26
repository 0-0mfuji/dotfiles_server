# Development Server (Debian)

Debian 13 (UEFI)。実際の開発処理はここのIncusコンテナで行う。

## 目次

- [構築の流れ](#構築の流れ)
- [このリポジトリのserver設定](#このリポジトリのserver設定)
- [自動Suspend](#自動suspend)
- [Windowsとのデュアルブート](#windowsとのデュアルブート)

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

アイドルが続いたら `systemctl suspend` (S3) する。SSH接続が無く、`systemd-inhibit` で
sleepを止めているジョブも無い状態が `DEV_IDLE_TIMEOUT` 秒 (既定3600) 続くと寝る。

```sh
sudo ./server/install-suspend.sh
```

判定の詳細、長時間ジョブからSuspendを止める方法、コンテナ内ジョブの注意は
[server/systemd/README.md](../server/systemd/README.md)。

> 外出先から起こすには、Raspberry Pi経由のWoLが必要。[raspi.md](raspi.md) を参照。

## Windowsとのデュアルブート

同じサーバーにゲーム用のWindowsを入れ、Debianから `boot-windows` で**次回の起動だけ**Windowsにする。
Windowsを閉じて起動し直せばDebianに戻る。GRUBの `grub-reboot` を使う (UEFI変数に書かない)。

```sh
sudo ./server/grub/setup-windows.sh   # GRUBに Windows を追加 (初回のみ)
boot-windows                          # 次回だけWindows
```

BIOS設定、Windowsのブートファイルの復旧、このサーバー固有の癖 (NVRAM、CMOSクリア、`B7`)、
Secure Bootが未達成であることは [windows.md](windows.md)。
