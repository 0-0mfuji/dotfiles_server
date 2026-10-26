# dotfiles

MacBookをThin Clientとして使い、実際の開発処理は自宅のDevelopment Server上で行うための
最小限のdotfiles。`dev <target>` 一発で、サーバーの起動からZed Remote Developmentでの
接続までを自動化する。

```sh
dev os    # サーバーが寝ていれば起こし、コンテナを起動し、Zedで開く
```

## 目次

- [ドキュメント](#ドキュメント)
- [全体像](#全体像)
- [リポジトリ構成](#リポジトリ構成)
- [設計原則](#設計原則)

## ドキュメント

| やりたいこと | ドキュメント |
| --- | --- |
| Macをセットアップする / **Macをリセットしたときの復旧** | [docs/macos.md](docs/macos.md) |
| Development Server (Debian) を構築する | [docs/server.md](docs/server.md) |
| **Windows** をデュアルブートで同居させ、`boot-windows` で切り替える | [docs/windows.md](docs/windows.md) |
| Raspberry Pi (Wake-on-LAN) を設定する | [docs/raspi.md](docs/raspi.md) |
| 開発環境 (Incusコンテナ) を作る・足す | [docs/environments.md](docs/environments.md) |
| **GPU** をコンテナから使う (導入・増設・Suspend) | [docs/gpu.md](docs/gpu.md) |
| **動画制作** (video / voice / blender) を**ゼロから再現する** | [docs/video.md](docs/video.md) |
| **Webアプリ開発** (web-dev: igakutteru) を**ゼロから再現する** | [docs/web.md](docs/web.md) |
| **Flutter開発** (flutter-dev: harmonic、Dart / Turso / Hono) | [docs/flutter.md](docs/flutter.md) |
| **私用秘書** (NanoMuse + SilverBullet、Gmail / outlook.jp / Plane / Karakeep / TimeTree) | [docs/secretary.md](docs/secretary.md) |
| `dev` コマンドの使い方、`projects.conf` | [docs/usage.md](docs/usage.md) |
| AI・ツールを**更新**する (`provision/run --update`, `bump-dsh`) | [docs/environments.md](docs/environments.md) |

初めて構築する場合の順序: **server → environments → raspi → macos → usage**

## 全体像

```
MacBook (Zed, ssh)
   │  Tailscale
   ├──▶ Raspberry Pi ──(Magic Packet)──▶ Development Server を起こす
   │
   └──▶ Development Server (Debian + Incus + ZFS)
            └── コンテナ (os-dev, lang-dev, ...)  ← ソースコードはここに置く
```

| リポジトリ | 役割 |
| --- | --- |
| **dotfiles_server** (これ) | Macの設定、`dev` コマンド、サーバー/Piのユーザー設定 |
| [dotfile_infra](https://github.com/0-0mfuji/dotfile_infra) | サーバーのホスト構築、Incusコンテナの定義 (OpenTofu) |
| 各プロジェクトのリポジトリ | ソースコード |

## リポジトリ構成

```
docs/      ドキュメント
macos/     Mac側の設定 (zsh, ssh, devコマンド本体)
server/    Development Server側の共通設定・自動Suspend・Windowsとのデュアルブート (bin/, grub/)
raspi/     Raspberry Pi用のWake-on-LANゲートウェイ
config/    dev コマンドのtarget定義 (projects.conf)・環境変数テンプレート
scripts/   dev が呼び出す個々の処理 (状態確認/Wake/Instance起動/clone/Editor起動)
```

## 設計原則

- MacBookはThin Client。開発環境やツールチェインは極力入れない。ソースもMacに置かない。
- 秘密情報・機器固有値 (IP, MACアドレス, 秘密鍵) はGit管理しない。
  `~/.ssh/config.local` と `~/.config/dev/local.env` に分離する。
- Incusコンテナの作成・更新・削除はこのリポジトリで行わない (dotfile_infraの責務)。
  ここから触るのは「状態確認」「起動」「接続確認」まで。
- 長時間ジョブ (build/CI/render/encode/AI/backup) は `systemd-inhibit` で自らSuspendを
  ブロックする。自動Suspendは、CPU使用率のような単純な指標を条件にしない。
  ただしコンテナ内のジョブは inhibitor を持てないので、レンダリング (`ffmpeg` / `blender` / Remotion) と
  AIエージェントだけは、プロセス名とCPU増分で補助的に検知する (`server/shell/auto-suspend.sh`)。

## 更新をサーバーへ反映する

Macで変更をコミットしてGitHubへpushした後、Development Serverで対象リポジトリをpullする。
サーバー上のリポジトリを直接編集したり、Macからファイルをコピーして反映したりせず、Gitを更新経路にする。

```sh
# Development Server: dotfiles_server
cd ~/dotfiles_server
git pull --ff-only

# OS設定を変更した場合は、該当するinstallerも実行する
./install.sh server
sudo ./server/install-suspend.sh  # 自動Suspend設定を変更した場合

# Development Server: dotfile_infra (別リポジトリ)
cd ~/dotfile_infra
git pull --ff-only
```

`dotfile_infra` のコンテナ設定を変更した場合は、pull後に対象環境の `provision/run` など、
各手順書に記載された反映コマンドを実行する。pull前にサーバー側の変更が残っている場合は、
消さずにコミットまたは退避してから更新する。
