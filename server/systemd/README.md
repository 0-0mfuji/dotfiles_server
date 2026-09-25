# dev-auto-suspend

2分ごとに `auto-suspend.sh` を実行し、以下がいずれも成立しない場合にのみ
`systemctl suspend` する。

- 確立済みのSSHセッションが無い
- `systemd-inhibit --mode=block` にsleepをブロックしている項目が無い
- 直近のアクティブ状態からidleTimeout秒(既定60分, `DEV_IDLE_TIMEOUT`)以上経過している

長時間ジョブ側の実装例:

```sh
systemd-inhibit --what=sleep --mode=block --who="blender-render" \
  --why="rendering job in progress" \
  blender -b scene.blend -a
```

GPU使用中もSuspendを禁止したい場合は、同様に該当ジョブの起動スクリプトを
`systemd-inhibit` でラップすること(このリポジトリでは汎用のGPU使用率監視は行わない)。

## セットアップ

```sh
sudo install -m 755 ../shell/auto-suspend.sh /usr/local/bin/dev-auto-suspend.sh
sudo install -m 644 dev-auto-suspend.service /etc/systemd/system/
sudo install -m 644 dev-auto-suspend.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dev-auto-suspend.timer
```

`server/install.sh` を使えば上記をまとめて実行できる。
