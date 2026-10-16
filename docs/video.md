# 動画制作環境 (video / voice / blender)

動画・音声・Vtuber動画の制作用に、Incusコンテナを3つ1組で作る。**サーバーを作り直しても、この手順どおりに流せば再現できる**
(定義は [dotfile_infra](https://github.com/0-0mfuji/dotfile_infra)、Mac側は このリポジトリ)。

## 目次

- [構成](#構成)
- [ゼロから作る手順](#ゼロから作る手順)
- [動作確認](#動作確認)
- [日々の使い方](#日々の使い方)
- [更新・追加](#更新追加)
- [うまくいかないとき](#うまくいかないとき)
- [サーバーで未確認の点](#サーバーで未確認の点)

## 構成

```
Mac ── dev video ──▶ voice-dev を起動 ─▶ video-dev を起動 ─▶ Remotion Studio をトンネルで開く + Zed
                                                              │
video-dev  (Remotion / ffmpeg / uv)   ── HTTP (VOICE_URL) ──▶ voice-dev (VOICEVOX ENGINE, CPU, :50021)
   │                                                              │
   └────────────── /srv/media (共有ボリューム。コンテナを作り直しても残る) ◀──┘
blender-dev (Blender 5.2、ヘッドレス。必要になるまで作らない) ── 同じ /srv/media
```

| コンテナ | 中身 | 定義の場所 |
| --- | --- | --- |
| `video-dev` | ffmpeg / mediainfo / sox / ImageMagick、日本語フォント、Remotion用のChromeライブラリ、Node (corepack)、uv、NVENC | `provision/agents.sh` の `install_video` |
| `voice-dev` | VOICEVOX ENGINE (CPU版)。`voicevox-engine.service` が常駐。**認証が無いので、Tailnetには出さない** | `install_voicevox` |
| `blender-dev` | Blender (公式tarball)、uv。`.blend` の作成はMacのGUIで、ここはレンダリング専用 | `install_blender` |

- **コンテナ同士は互いを知らない。** `video` が `voice` を呼ぶ先は、`VOICE_URL` (環境変数) だけで決まる。起動は `dev` が担当する
  (`projects.conf` の `deps` 列)。コンテナからホストの `incus` は呼べない。
- 版とSHA-256は `dotfile_infra/provision/versions.env` で固定している。
- npm・pip のライブラリは、プロジェクトの lockfile で固定する。雛形は `dotfile_infra/templates/video` ([README](https://github.com/0-0mfuji/dotfile_infra/blob/main/templates/video/README.md))。

## ゼロから作る手順

前提: [server.md](server.md) のホスト構築 (Debian + Incus + ZFS + NVIDIA) が済んでいて、[environments.md](environments.md) の
`tofu apply` が一度は通っていること。

### 1. ホスト: 共有ボリュームを作る (サーバー上)

```sh
cd ~/dotfile_infra/host
sudo MEDIA_QUOTA=500G ./setup.sh 45     # dev-tank/media -> /srv/media (recordsize=1M)
zfs list dev-tank/media                  # 確認
sudo zfs set quota=1T dev-tank/media     # 後から変えるとき
```

- Incus の storage pool (`dev-tank/incus`) の**外**にあるので、コンテナや Incus を作り直しても残る。
- `MEDIA_QUOTA` は作成時だけ使う。空き容量 (`zpool list`) を見て決める。
- 新しいディスクで最初から作るときは、`storage-init` が最後にこのstepを呼ぶ。

### 2. コンテナを定義して作る (サーバー上)

`~/dotfile_infra/terraform.tfvars` の `dev_instances` に、`terraform.tfvars.example` の `video` / `voice` (必要なら `blender`) を写す。

- `ip` は**他と重ならない値**にする。`voice` の `ip` が、`VOICE_URL` の宛先になる。
- `voice` は `gpu = false` (VOICEVOXはCPU版。VRAM 8GB を whisper / Blender に残す)、`web_port` は付けない。
- `media = "rw"` で、`/srv/media` が同じパスに渡る (`shift=true` で、コンテナ内の `dev` が読み書きできる)。

```sh
cd ~/dotfile_infra && git pull
tofu plan        # video / voice に media デバイスが付くことを確認
tofu apply
```

### 3. コンテナの中身を整える (サーバー上)

`~/.config/dev/provision.env` (サーバー上・Git管理外) に、VOICEVOX の場所を書く。

```sh
VOICE_URL=http://10.10.0.21:50021        # voice の ip。video-dev の ~/.profile と ~/.bashrc に入る
```

```sh
./provision/run voice-dev video-dev      # 初回は voice が約1.8GBのダウンロード。video-dev は8GiB以上のメモリが要る
./provision/run blender-dev              # 作った場合だけ
```

何度流しても同じ結果になる。ログに `voicevox: serving on :50021`、`video: h264_nvenc: ok`、`video: /srv/media/{audio,renders,out}: ok` が出る。

### 4. Mac: SSH と projects.conf

`~/.ssh/config.local` (Git管理外) に足す。`voice-dev` / `blender-dev` は `dev` が起動するだけなので、sshは不要。

```
Host video-dev
    HostName 10.10.0.20        # tfvars の video の ip
    User dev
    ProxyJump dev-server
```

[config/projects.conf](../config/projects.conf) の `video` 行は、すでに入っている。

```
video     video-dev     ~/src/video      video-dev   -   git   voice-dev   3000
```

`repo` は、自分の動画プロジェクトのGitHub URL に変える (`-` なら自動cloneしない)。

### 5. プロジェクトを置く

雛形は dotfile_infra の `templates/video` (サーバー上の `~/dotfile_infra`) にある。サーバーから `video-dev` へ入れる。

```sh
# サーバー上で
incus exec video-dev --user 1000 --group 1000 --cwd /home/dev --env HOME=/home/dev -- mkdir -p src
incus file push -r --uid 1000 --gid 1000 ~/dotfile_infra/templates/video video-dev/home/dev/src/
# コンテナ内で (Zed のターミナルなど)
cd ~/src/video && git init && pnpm install --frozen-lockfile && uv sync
```

自分のGitHubリポジトリにして管理するなら、`projects.conf` の `repo` にそのURLを書く (`dev video` が自動cloneする)。

以降は `dev video` だけで、voice-dev と video-dev の起動、Remotion Studio (SSHトンネル)、Zed、Web UI が開く。
`dev --studio video` なら Studio だけ。

## 動作確認

サーバーでしか確認できない項目。上から順に。

| # | 確認 | 期待する結果 |
| --- | --- | --- |
| 1 | サーバー: `zfs list dev-tank/media`、`ls -ld /srv/media` | データセットがある |
| 2 | サーバー: `incus exec voice-dev -- curl -s http://127.0.0.1:50021/version` | バージョン (0.25.2) が返る |
| 3 | `video-dev`: `curl -s $VOICE_URL/version` | 同じバージョン。返らなければ `VOICE_URL` / 固定IP / voice-dev の起動を疑う |
| 4 | `video-dev`: `touch /srv/media/out/x && ls -l /srv/media/out` | 書ける (`dev` ユーザー) |
| 5 | `video-dev`: `fc-list :lang=ja \| head -3`、`ffmpeg -version \| head -1` | 日本語フォント (Noto CJK) と ffmpeg がある |
| 6 | `video-dev`: `python3 scripts/voice.py "こんにちは" --out /srv/media/audio/hello` (プロジェクト内) | `hello.wav` と `hello.query.json` ができる |
| 7 | `dev video` | voice-dev が起動し、Studio がMacのブラウザで開く |
| 8 | `video-dev`: `pnpm render Hello out/hello.mp4` | 日本語の字幕が豆腐 (□) にならない |
| 9 | レンダリング中にSSHを全部切り、サーバーで `journalctl -t dev-auto-suspend --since "10 min ago"` | `active (agent)` が出ていて、寝ない |

## 日々の使い方

```sh
dev video            # voice-dev を起こし、video-dev を開く (Zed + Web UI + Studio)
dev --studio video   # Studio だけ
```

- Remotion Studio のトンネルは、開いている間は自動Suspendを止める。4時間で閉じる (`DEV_WEB_TUNNEL_TTL`)。
- 書き出し (`ffmpeg` / `blender` / `remotion render`) は、CPUを使っている間はSuspendされない。SSHを切っても寝ない。
  しきい値と検知するプロセスは [server/systemd/README.md](../server/systemd/README.md)。
- 素材と成果物は `/srv/media/{audio,renders,out}`。Macへは `rsync -av video-dev:/srv/media/out/ ~/Movies/out/`。
- 重い作業を同時に流すと、GPUのVRAM (8GB) を取り合う。whisper と Blender は、1つずつ。

## 更新・追加

| やりたいこと | 方法 |
| --- | --- |
| VOICEVOX / Blender / uv の版を上げる | `provision/versions.env` の版とSHA-256 (GitHubのdigest / blender.org の `.sha256`) を書き換えて、`./provision/run <コンテナ>` |
| Remotion の版を上げる | プロジェクトで全 `@remotion/*` を同じ版にして lockfile を更新。雛形も同時に直す |
| Pythonのライブラリを足す | プロジェクトの `pyproject.toml` に足して `uv lock` |
| Blender を使い始める | `terraform.tfvars` の `blender` を有効にして `tofu apply` -> `./provision/run blender-dev`。VRM / MMD のアドオンは、使う段階でタグを固定して足す |
| `voice-dev` を作り直す | `tofu apply -replace='incus_instance.dev["voice"]'` -> `./provision/run voice-dev`。`/srv/media` は残る |

作り直すとコンテナ内のデータは消える。**ソースは GitHub に push、素材は `/srv/media` に置く。**

## うまくいかないとき

| 症状 | 確認 |
| --- | --- |
| `voice.py` が接続できない | `incus list` で voice-dev が RUNNING か。起動直後はAPIが応答するまで数十秒かかる。`incus exec voice-dev -- journalctl -u voicevox-engine -n 50` |
| `VOICE_URL が未設定` | サーバーの `~/.config/dev/provision.env` に書いて `./provision/run video-dev`。新しいシェルで読み直す |
| provision が `voicevox: checksum FAILED` | `versions.env` の版とSHA-256が合っているか。ダウンロードが途中で切れていないか (約1.8GB) |
| provision が `video: apt install FAILED` | ログの失敗したパッケージ名 (Debianの版で名前が違うことがある) を、`VIDEO_PKGS` で直す |
| Studio が開かない | コンテナの `~/.cache/remotion-studio.log`。プロジェクトに `node_modules` があるか |
| 字幕が豆腐になる | `fc-list :lang=ja` が空 -> `./provision/run video-dev` (`fonts-noto-cjk`) |
| `/srv/media` に書けない | tofu の `media = "rw"` と `apply` 済みか。`ls -ld /srv/media` の所有者 (`shift=true` で `dev` に見えるはず) |
| `h264_nvenc` が使えない | [gpu.md](gpu.md#nvenc-ffmpeg-のgpuエンコード)。CPUの `libx264` なら書き出せる |
| レンダリング中に寝た | `journalctl -t dev-auto-suspend`。対象のプロセス名が合っているか (`DEV_KEEP_AWAKE_PROCS`) |

## サーバーで未確認の点

この構成は、書いてあるだけで、サーバーでは**まだ一度も実行していない**。最初の実行で、次を確かめる (違えば、該当の箇所を直して、ここも更新する)。

- Remotion (Chrome) 用のaptパッケージ名 (`libasound2t64` など) が、Debian 13 で通るか。
- VOICEVOX の7zを展開したあとのディレクトリ構成 (`run` の場所)。
- `shift=true` のdiskデバイスが、ZFS の `dev-tank/media` で期待どおり動くか。
- NVENC に必要な capability が、Incusの `gpu` デバイスで渡るか。
- Remotion のライセンス条件 (収益化・会社利用)。
