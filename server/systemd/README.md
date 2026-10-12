# dev-auto-suspend

2分ごとに `auto-suspend.sh` を実行し、アイドルが続いたら `systemctl suspend` (S3) する。

## 判定

次の**どちらにも該当せず**、最後にアクティブだった時から `DEV_IDLE_TIMEOUT` 秒
(既定3600=60分) 以上経っているときだけSuspendする。

| アクティブ条件 | 例 |
| --- | --- |
| 確立済みのSSH接続がある | Macからの接続、ZedがProxyJump経由でコンテナに繋いでいる間 |
| `systemd-inhibit` で sleep を **block** しているものがある | ビルド、レンダー、エンコード、バックアップ |

`delay` 型のロック (NetworkManager等) は無視する。CPU使用率は見ない。

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
DEV_AUTO_SUSPEND_DRY_RUN=1 DEV_AUTO_SUSPEND_STATE=/tmp/x /usr/local/bin/dev-auto-suspend.sh
journalctl -t dev-auto-suspend       # 実際にSuspendした記録
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
- 復帰後はアイドルタイマーが仕切り直される。
