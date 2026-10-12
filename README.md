# dotfiles

MacBookをThin Clientとして使い、実際の開発処理は自宅のDevelopment Server上で
行うための最小限のdotfiles。`dev <target>` 一発で、Development Serverの起動から
Zed Remote Developmentでの接続までを自動化する。

## 目次

- [構成](#構成)
- [導入方法](#導入方法)
  - [MacBook](#macbook)
  - [Development Server (Debian)](#development-server-debian)
  - [Raspberry Pi](#raspberry-pi)
- [環境の作成 (dotfile_infra)](#環境の作成-dotfile_infra)
- [使い方](#使い方)
- [設計原則](#設計原則)

## 構成

```
macos/     MacBook側の設定 (zsh, ssh, zed, devコマンド本体)
server/    Development Server側の共通設定・自動Suspend
raspi/     Raspberry Pi用のWake-on-LANゲートウェイ
config/    dev コマンドのtarget定義・環境変数テンプレート
scripts/   dev コマンドが呼び出す個々の処理 (状態確認/Wake/Instance起動/clone/Editor起動)
```

Incus環境そのもの(instance定義・profile・provisioning等)はこのリポジトリの
責務外で、[dotfile_infra](#環境の作成-dotfile_infra) が管理する。ここでは
「利用可能なリモート開発環境が存在すること」だけを前提にする。

## 導入方法

### MacBook

```sh
./install.sh macos
```

シンボリックリンクを張るだけで、既存ファイルは上書きしない。`~/.ssh/config` が
シンボリックリンクの場合は自動編集せず、追記すべき2行(`Include ~/.ssh/config.d/dotfiles`
と `Include ~/.ssh/config.local`)を表示するので、手動で先頭に足す。

その後、以下の2ファイルを編集する(どちらもGit管理外):

| ファイル | 内容 |
| --- | --- |
| `~/.ssh/config.local` | 実際のHost定義 (IP, ProxyJump, User等) |
| `~/.config/dev/local.env` | `DEV_SERVER_HOST` / `DEV_SERVER_MAC` / `RASPI_HOST` |

`~/.ssh/config.local` の例 (コンテナはDevelopment Server経由で入る):

```
Host dev-server
    HostName 100.x.x.x            # Tailscale IP (自宅内でも外出先でも同じ)
    User <user>
    IdentityFile ~/.ssh/<key>
    IdentitiesOnly yes

Host os-dev
    HostName 10.10.0.13           # dotfile_infra の terraform.tfvars の ip と合わせる
    User dev
    ProxyJump dev-server
    IdentityFile ~/.ssh/<key>
    IdentitiesOnly yes
```

### Development Server (Debian)

```sh
./install.sh server
```

共通のshell/git設定をリンクする。自動Suspend(systemd)の有効化はsudoが
必要なため、表示されるコマンドを手動で実行する。詳細は
[server/systemd/README.md](server/systemd/README.md)。

### Raspberry Pi

```sh
./install.sh raspi <raspi-ssh-host>
```

`dev-server-wake` を `/usr/local/bin/` にインストールする
(`wakeonlan` または `etherwake` が別途必要)。

## 環境の作成 (dotfile_infra)

`dev <target>` で開く先のIncus Instance自体は、別リポジトリ
[dotfile_infra](https://github.com/0-0mfuji/dotfile_infra) の
[OpenTofu](https://opentofu.org/)(Terraform互換)で作成する。Development
Server上で実行する(MacBookには何も入れない)。

```sh
# Development Server上で
git clone git@github.com:0-0mfuji/dotfile_infra.git
cd dotfile_infra

# 1. ホスト構築 (SSH/WoL/ZFS/Incus導入、ディスク初期化)。手順は host/README.md
cd host
sudo ./setup.sh
sudo ./storage-init /dev/disk/by-id/<disk-id>   # ディスクを消す。対象を確認して実行
cd ..

# 2. Instanceの作成
./install.sh   # OpenTofu CLIが未導入の場合のみ
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # 項目は dotfile_infra のREADME参照
tofu init
tofu apply
```

`dev_instances` に定義したkeyはそのまま `<key>-dev` というInstance名になる。
この名前を [config/projects.conf](config/projects.conf) のinstance列に
書いておくと、`dev <target>` 実行時に停止中のInstanceを自動起動する。

Instanceの追加・スペック変更は `terraform.tfvars` を編集して
`tofu apply` するだけでよい。詳細は
[dotfile_infraのREADME](https://github.com/0-0mfuji/dotfile_infra#readme)
を参照。

## 使い方

```sh
dev os        # config/projects.conf の "os" targetを開く
dev cpu
dev flutter
```

`dev <target>` は次を順に行い、Zed Remote Developmentで開く。

1. Development Serverに接続できなければ、Raspberry Pi経由でWake-on-LAN
2. SSHが通るまで待つ
3. `projects.conf` にinstance名があれば、停止中のInstanceを起動
4. `repo` が設定されていて、コンテナ内に `path` が無ければ `git clone`
   (Macのsshエージェントを転送して認証する。privateでもOK。秘密鍵はコンテナに置かない)
5. Zedで `path` を開く

**ソースコードはすべてコンテナ内 (`path`) に置き、Macには置かない。**
Instanceを作り直すと中身は消えるので、重要な変更は必ずGitHubへpushすること。

targetの追加・変更は [config/projects.conf](config/projects.conf) を編集する
だけでよい。1つのtargetに設定できるリポジトリは1つ。複数ある場合は
別のtargetとして行を足す。

## 設計原則

- MacBookはThin Client。開発環境やツールチェインは極力入れない。
- 秘密情報・マシン固有値(IP, MACアドレス, 実Host名)はGit管理しない。
  `~/.ssh/config.local` と `~/.config/dev/local.env` に分離する。
- Incus Instanceの作成・更新・削除はこのリポジトリで行わない。
  ここから触るのは「状態確認」「起動」「接続確認」まで。
- 長時間ジョブ(build/CI/render/encode/AI/backup)は `systemd-inhibit` で
  自らSuspendをブロックする。自動Suspend側はCPU使用率のような単純な指標を
  条件にしない。
