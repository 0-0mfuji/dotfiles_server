# Raspberry Pi (Wake Gateway)

常時稼働のRaspberry Piから、Development ServerへWake-on-LANを送る。

```
Mac --(Tailscale)--> Raspberry Pi --(Magic Packet)--> 管理用1GbE NIC --> Development Server
```

## 目次

- [導入](#導入)
- [動作確認](#動作確認)
- [うまく起きないとき](#うまく起きないとき)

## 導入

Macで、Piに `ssh raspi` できる状態にしてから実行する。

```sh
./install.sh raspi raspi
```

`dev-server-wake` を `/usr/local/bin/` に入れる。Pi側に `wakeonlan` (または `etherwake`) が
必要。無ければ先にPi上で `sudo apt install wakeonlan` を実行する。
インストーラはPi上で `sudo` を非対話で実行するため、Piのユーザーがパスワードなしでsudoを使える必要がある
(Raspberry Pi OSの既定)。使えない場合は、Piにログインして `/usr/local/bin/` へ手動でコピーする。

Development ServerのMACアドレスは、サーバーで `sudo ./setup.sh` の `20-network` が表示する。
Macの `~/.config/dev/local.env` の `DEV_SERVER_MAC` に設定する。

## 動作確認

サーバーをSuspendした状態で、Macから実行する。

```sh
ssh raspi 'dev-server-wake <DEV_SERVER_MAC>'
```

1分ほどでサーバーにSSHできれば成功。`dev <target>` は、サーバーに繋がらないときにこれを自動で行う。

## うまく起きないとき

- BIOSで、PCIE/LANからのウェイクアップ (Wake on LAN / PCIE) が有効か確認する。
- サーバーで `ethtool <iface> | grep Wake-on` が `g` になっているか確認する
  (`wol@<iface>.service` が起動時に設定する)。
- **Suspendした直後にすぐ起きてしまう**場合は、USBコントローラのウェイクアップが原因のことが多い
  (キーボード/マウス/USBカードのPME)。`dotfile_infra` の `20-network` が `usb-wake-off.service` で
  無効にする。確認は `grep . /sys/bus/pci/devices/*/power/wakeup` で、WoLに使う有線NICだけ
  `enabled`、USBコントローラは `disabled` が正しい。
- Magic Packetは**管理用1GbE NIC**宛に送る。10GbE NICはWoLに使わない。
- Piとサーバーが同じLAN (ブロードキャストが届く範囲) にあるか確認する。
