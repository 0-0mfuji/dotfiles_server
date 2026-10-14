# dev-auto-suspend

2分ごとに `auto-suspend.sh` を実行し、アイドルが続いたら `systemctl suspend` (S3) する。

## 判定

次の**どちらにも該当せず**、最後にアクティブだった時から `DEV_IDLE_TIMEOUT` 秒
(既定3600=60分) 以上経っているときだけSuspendする。

| アクティブ条件 | 例 |
| --- | --- |
| 確立済みのSSH接続がある | Macからの接続、ZedがProxyJump経由でコンテナに繋いでいる間 |
| `systemd-inhibit` で sleep を **block** しているものがある | ビルド、レンダー、エンコード、バックアップ |
| AIエージェントのプロセスが、直近でCPUを使っている | コンテナ内の `claude` / `codex` / `dsh` が作業中 |
| **GPUが計算中** (使用率が閾値以上) | コンテナ内のPythonでの学習など。VRAMを持つだけの放置ノートブックは対象外。詳細は [docs/gpu.md](../../docs/gpu.md) |

`delay` 型のロック (NetworkManager等) は無視する。マシン全体のCPU使用率は見ない。

### AIエージェントの活動検出

コンテナ内のプロセスは、ホストの `/proc` からそのまま見える。コマンドラインが `claude` / `codex` /
`dsh web` に一致するプロセスについて、**2分ごとの実行間隔で増えたCPU時間**を数える。

- 増えたCPU時間が閾値 (既定100ticks = 約1秒) 以上なら「アクティブ」。作業をやめて60分で寝る。
- プロンプトを開いたまま放置した `claude` や、常駐する `dsh web` の待機は、CPUをほぼ使わない
  (実測で `dsh web` は60秒で0.11秒) ので、「アクティブ」にならない。
- pidと起動時刻で識別する。新しく起動したプロセスは、起動時のCPU時間を増分とみなす。
- 起動直後など、前回の記録が無いときは「アクティブ」とは見なさない。

| 設定 (`/etc/default/dev-auto-suspend`) | 既定 | 意味 |
| --- | --- | --- |
| `DEV_KEEP_AWAKE_PROCS` | `claude` / `codex` / `bin.ts web` | 対象プロセスのコマンドラインに一致する拡張正規表現 |
| `DEV_KEEP_AWAKE_CPU_TICKS` | `100` | 実行間隔あたりのCPU時間の閾値 (1秒=100ticks) |
| `DEV_KEEP_AWAKE_GPU_UTIL` | `5` | GPU使用率(%)の閾値。`DEV_GPU_SAMPLES`回 (既定3)、1秒おきに見る |

閾値は、実際にエージェントを動かして、判定ログ (DRY_RUN) を見ながら調整する。

## 導入

```sh
sudo ./server/install-suspend.sh
```

`/usr/local/bin/dev-auto-suspend.sh` とsystemdのunit/timerを入れて、timerを有効にする。
アイドル時間を変える場合は `/etc/default/dev-auto-suspend` に書いて、`sudo systemctl daemon-reload`:

```
DEV_IDLE_TIMEOUT=7200
```

## 動作確認

実際にはSuspendせず、判定だけ見る:

```sh
DEV_AUTO_SUSPEND_DRY_RUN=1 DEV_AUTO_SUSPEND_STATE=/tmp/x DEV_AUTO_SUSPEND_CPU_STATE=/tmp/xc /usr/local/bin/dev-auto-suspend.sh
journalctl -t dev-auto-suspend       # 2分ごとの判定の記録 (Suspendした記録も、ここに出る)
# 例: active (ssh) ssh=2 inhibit=0 cpu=52/100 gpu=0   <- sshが理由で起きている
#     idle 1800s/3600s ssh=0 inhibit=0 cpu=7/100 gpu=0  <- idleが30分続いている
# どの理由がどれだけ続いたかを数える:
journalctl -t dev-auto-suspend --since '24 hours ago' -o cat | sed -E 's/ .*//; s/^(active) \((.*)\).*/\1:\2/' | sort | uniq -c
systemctl list-timers dev-auto-suspend.timer
```

## 長時間ジョブからSuspendを止める

サーバー上で、ジョブを `systemd-inhibit` でラップする:

```sh
systemd-inhibit --what=sleep --mode=block --who=blender-render \
  --why="rendering job in progress" \
  blender -b scene.blend -a
```

**コンテナ内のジョブは、ホストのinhibitorを持てない。** コンテナ内で長時間ジョブを走らせるときは、
Macからそのコンテナへのssh接続を開いたままにする (`ssh os-dev` + tmux 等)。
接続が生きている間は、サーバー側でSSH接続として検出される。

GPUを使うジョブも同様にラップすること (GPU使用率の自動監視はしない)。

## 注意

- Macで**Zedやsshを開いたままだと、サーバーは寝ない**。閉じてから60分後にSuspendする。
- 復帰後はアイドルタイマーが仕切り直される (`/usr/lib/systemd/system-sleep/dev-auto-suspend` が復帰時に記録する)。
