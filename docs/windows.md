# Windows とのデュアルブート

Development Server (Debian) に、ゲーム用のWindowsを同居させ、**Debianから `boot-windows` を実行すると、
次の1回だけWindowsで起動する**。Windowsをシャットダウンして、もう一度起動すればDebianに戻る。

```sh
boot-windows      # 次回だけWindows。確認して再起動
boot-windows -n   # 設定だけ (再起動しない)
boot-windows -y   # 確認なしで再起動
```

## 目次

- [構成](#構成)
- [しくみ](#しくみ)
- [構築手順](#構築手順)
- [使い方](#使い方)
- [Windowsが起動しなくなったとき (ブートファイルの復旧)](#windowsが起動しなくなったとき-ブートファイルの復旧)
- [このサーバーの癖 (検証済み)](#このサーバーの癖-検証済み)
- [Secure Boot (未達成)](#secure-boot-未達成)
- [MOKの登録 (Secure Bootに備える)](#mokの登録-secure-bootに備える)
- [未検証の案](#未検証の案)

## 構成

| 項目 | 内容 |
| --- | --- |
| マザーボード | ASUS Z10PE-D8 WS (BIOS 4301, AMI Aptio 2.17 / UEFI 2.4) |
| Debian | NVMe (Samsung 980 PRO)。ESP = `nvme0n1p1` (976MB, vfat) |
| Windows | SATA SSD (Apacer)。GPT。パーティションは MSR / NTFS / 回復 の3つだけで、**自前のESPを持たない** |
| Windowsのブートファイル | **Debianと同じESP** の `\EFI\Microsoft\Boot\` に置く |
| PCIeカード | RTX 3070 Ti、Emulex OneConnect 10Gb (SFP+) ×2ポート、Intel 82580 (4ポートGbE) |

## しくみ

```
電源ON → UEFI → shim → GRUB ─┬─ (既定) Debian
                             └─ (grub-reboot で指定した次回だけ) Windows
                                  └ chainloader /EFI/Microsoft/Boot/bootmgfw.efi
```

- 「次回だけ」の記録先は `/boot/grub/grubenv` (ext4上のファイル)。**UEFI変数 (NVRAM) には書かない**。
- `GRUB_DEFAULT=saved`、`saved_entry=0` (= Debian)。`grub-reboot` は1回で消えるので、Windowsを閉じて起動し直すとDebianに戻る。
- UEFIの `BootNext` (`efibootmgr -n`) を使わない理由は [このサーバーの癖](#このサーバーの癖-検証済み)。

## 構築手順

### 1. Windowsのブートファイルを、DebianのESPに置く

ESPに `EFI/Microsoft` があれば不要 (`sudo ls /boot/efi/EFI` で確認)。無いとき (WindowsのESPが
別ディスクにあって消えた、など) は [復旧手順](#windowsが起動しなくなったとき-ブートファイルの復旧) を行う。

### 2. BIOS設定 (起動時に `Del`)

| 場所 | 項目 | 値 |
| --- | --- | --- |
| `Advanced` → `CSM Configuration` | `CSM Support` | `Enabled` (**`Disabled` にしない**。[B7](#secure-boot-未達成)) |
| 同 | `Boot option filter` | **`UEFI only`** (LegacyのBBSエントリが毎回作り直されるのを止める) |
| 同 | `Network` / `Video` / `Other PCI devices` | `Legacy` (初期値) |
| 同 | `Storage` | `UEFI` |
| `Advanced` → `PCI Subsystem Settings` | `Above 4G Decoding` | `Disabled` (初期値) |
| `Boot` | `Boot Option #1` | `debian` |
| `Boot` | `Boot Option #2` | `Windows Boot Manager` |

### 3. サーバーにGRUBのエントリを追加する

```sh
git clone git@github.com:0-0mfuji/dotfiles_server.git   # 済みなら git pull
cd dotfiles_server
./server/install.sh                    # boot-windows を ~/.local/bin にリンク
sudo ./server/grub/setup-windows.sh    # GRUBに Windows を追加
```

`setup-windows.sh` がすること (何度実行しても同じ結果):

1. `/etc/default/grub` / `/etc/grub.d/40_custom` / `/boot/grub/grub.cfg` を日時つきでバックアップ
2. `GRUB_DEFAULT=saved`、`GRUB_DISABLE_OS_PROBER=true` (40_customの `Windows` との重複検出を避ける)
3. `40_custom` に `Windows` (`--id windows`) を追加。ESPのUUIDはマウント中のESPから取得
4. `update-grub` → `grub-script-check` で構文検証
5. `grub-set-default 0` (既定をDebianに固定)

> 以前、`~/.bashrc` に手書きの `boot-windows` 関数を入れている場合は消す (関数がスクリプトより優先される)。

## 使い方

```sh
boot-windows
```

1. 「次回起動: Windows (GRUB: windows)」と出る。確認に `y` で再起動。
2. GRUBのメニュー (5秒) から、自動で Windows が起動する。
3. Windowsを**シャットダウン**し、電源を入れ直すと Debian が起動する。

WoLで起こした直後 (Suspend復帰後) でも動く (NVRAMを使わないため)。

## Windowsが起動しなくなったとき (ブートファイルの復旧)

Debianの入れ直しなどでESPを初期化すると、`\EFI\Microsoft` が消える。Windows本体 (NTFS) は無事なので、
ブートファイルだけ作り直せばよい。

### 手順A: 修復用USBをMacで作る

`install.wim` は不要 (`bcdboot` はインストール済みのWindowsからブートファイルを作るため)。
`boot.wim` だけ入れれば、セットアップ画面からコマンドプロンプトを開ける。

```sh
brew install sevenzip
diskutil list external                              # USBの /dev/diskN を確認 (間違えると別のディスクが消える)
diskutil eraseDisk MS-DOS WINUSB MBR /dev/diskN     # USBの中身は全部消える
7zz l ~/Downloads/Windows11_*.iso | grep -E "Physical Size|install.wim"   # ISOが欠けていないか
7zz x -aoa -o/Volumes/WINUSB '-x!sources/install.wim' ~/Downloads/Windows11_*.iso
diskutil eject /dev/diskN
```

| 注意 | 理由 |
| --- | --- |
| `hdiutil mount` / `rsync` で、マウントしたISOからコピーしない | WindowsのISOはUDF。macOSのマウントは `Unknown error: 10000` で読めない |
| ダウンロード前に、Macの空きを確認 (`df -h /`) | 空きが足りないと、ISOが**途中で切れた状態で保存される**。`7zz l` の `Physical Size` が、中身の合計 (`install.wim` 約8GB + `boot.wim`) 以上か見る |

### 手順B: サーバーでUSBから起動して、`bcdboot` を実行する

1. USBを挿して再起動。BIOSの `Boot` → `Boot Option #1` で **`UEFI:` が付いたUSB** を選んで `F10`
   (起動時の `F8` ブートメニューでも選べるはず。未検証)。`UEFI:` が付かない方 (Legacy) を選ぶと、
   `Intel Boot Agent` (PXE) まで落ちて起動しない。
2. Windowsセットアップの最初の画面で `Shift+F10` (コマンドプロンプト)。インストールは進めない。
3. 次を実行する。

```
diskpart
list vol
select vol <ESPの番号>      ← FAT32 約1GB (Debianのもの)。USB (FAT32 約60GB) と間違えない
assign letter=S
select vol <Windowsの番号>  ← NTFS 約476GB
assign letter=W
exit
cd /d W:
dir                         ← Windows / Users / Program Files が見えること
bcdboot %cd%Windows /s S: /f UEFI
dir S:\EFI                  ← Microsoft / debian / BOOT が見えれば成功
wpeutil reboot
```

> セットアップ環境のキーボードがUS配列で `\` が打てないとき、`%cd%` (= `W:\`) で代用する。
> 日本語配列に切り替えるなら `wpeutil SetKeyboardLayout 0411:00000411` (未検証)。

再起動の直前にUSBを抜く。CMOSクリア後などで起動順が変わっているときは、BIOSの `Boot Option #1` を `debian` に戻す。

## このサーバーの癖 (検証済み)

| 現象 | 確認した内容 |
| --- | --- |
| 起動のたびに、Legacyの `Hard Drive` / `Network Card` エントリが作り直される | `Boot option filter` を `UEFI only` にすると止まる (再起動後に増えないことを確認) |
| OSから、`Boot####` / `BootNext` 以外のUEFI変数を**新規作成**できない | `dd` で名前・GUID・属性・サイズを変えて試し、すべて `EINVAL`。既存変数の更新は成功 |
| `mokutil --import` が `Failed to enroll new keys` | 上と同じ原因 (`MokNew` を作れない)。**MokManager (`mmx64.efi`) から登録すれば通る** ([MOKの登録](#mokの登録-secure-bootに備える)) |
| Suspend復帰後は、`BootNext` も作れない (`efibootmgr -n` が `EIO`) | 起動直後は成功、復帰後は失敗。**自動Suspendと相性が悪いので、GRUB方式にした** |
| `efibootmgr -B` で消したエントリが、再起動で戻ることがある | 重複した `debian` (`GRUBX64.EFI`) など。害はない |
| **CMOSクリアすると、起動順が初期化されて Windows が先に起動する** | BIOSで `Boot Option #1` を `debian` に戻す |
| **CMOSクリアすると、MOKに登録した鍵が消える** | `mokutil --list-enrolled` が空になる。Secure Bootを使うなら再登録 |
| `mokutil --revoke-import` が `Invalid argument` | `MokNew` の0バイトの抜け殻。**再起動で消える** |

実機のNVRAMの空きは、変数の合計サイズ (約40KB) だけでは判断できない。容量が原因とは言い切れていない。

## Secure Boot (未達成)

Valorant (Riot Vanguard) は、Secure Boot とTPM 2.0を要求する、と理解している (Riotの現行の要件は、公式で確認すること)。
TPMはWindows側で有効 (`tpm.msc`)。以前このPCでValorantが動いていた。
**Secure Bootは、まだ有効にできていない。**

| 事実 | 内容 |
| --- | --- |
| BIOSの警告 | `CSM is Loaded! Disable the CSM in Setup.` — CSMが有効だと、`Secure Boot` を `Enabled` にできない |
| CSMを `Disabled` にすると | 基板のQ-Codeが **`B7`** で止まり、画面は出ず、BIOSにもブートメニューにも入れない。**CMOSクリア** (`CLRTC1`) で戻す |
| 試した組み合わせ (いずれも `B7`) | `CSM Support: Disabled` 単独 / `Above 4G Decoding: Enabled` + `Network: UEFI` + `Other PCI devices: UEFI` + `CSM Support: Disabled` |
| `PCI Subsystem Settings` | スロット別のOption ROM設定は無い (`Load RT32 Image` / `Above 4G Decoding` / `SR-IOV` のみ) |
| BIOS | 4301 (2020/06/05、ASUS公式の最新) |

**`B7` の原因は特定できていない。** 仮説 (どれも未検証):

1. BIOSのNVRAM領域の不整合。CSM変更時の設定の書き換え (Configuration Reset) が失敗する。OSからの変数作成失敗・Suspend復帰後の `EIO` と、症状が同じ領域に集まっている。
2. PCIeカード (Emulex OneConnect 等) のOption ROMが、UEFIだけでは初期化できない。

Secure Bootを有効にする手順 (CSMを無効にできたとき):

1. `Advanced` → `CSM Configuration` → `CSM Support: Disabled` → `F10` → 再起動
2. もう一度BIOSへ。`Security` → `Secure Boot` → `Secure Boot: Enabled` (`Secure Boot Mode` は `Custom` のまま。PK登録済み = `System Mode: User`)
3. [MOKの登録](#mokの登録-secure-bootに備える) が済んでいることを確認してから再起動

## MOKの登録 (Secure Bootに備える)

Secure Bootを有効にすると、署名の無いカーネルモジュールは読み込めない。このサーバーの **ZFS (`zfs-dkms`) と
NVIDIA (`nvidia-kernel-dkms`) はDKMSでビルド**されるので、DKMSの署名鍵 (`/var/lib/dkms/mok.pub`) をMOKに登録しておく。
登録しないままSecure Bootを有効にすると、`dev-tank` (Incusのストレージ) が使えなくなる。

`mokutil --import` はこのサーバーでは失敗するので、**起動前に MokManager (`mmx64.efi`) を直接起動して登録する**。
**モニターとキーボードが必要。Suspend復帰前の、起動直後に行う** (復帰後はNVRAMに書けない)。

```sh
sudo cp /var/lib/dkms/mok.pub /boot/efi/dkms-mok.cer
sudo efibootmgr -c -d /dev/nvme0n1 -p 1 -L "MokManager" -l '\EFI\debian\mmx64.efi'
efibootmgr | cut -c1-70      # MokManager が BootOrder の先頭になる
sudo systemctl reboot
```

再起動すると青い画面になる。**何かキーを押さないと、10秒ほどでそのままDebianが起動する。**

1. `Enroll key from disk`
2. **NVMe側のボリューム** (`Pci(0x1,0x0)/Pci(0x0,0x0)/...`。SATAのものはWindowsのディスク) を選ぶ
3. `dkms-mok.cer` を選ぶ → `View key 0` で `CN=DKMS module signing key` を確認 → `Continue` → `Yes` → `Reboot`

起動後、起動順を戻して確認する。

```sh
sudo efibootmgr -o 0004,0003         # 番号は efibootmgr の表示に合わせる (debian, Windows)
sudo efibootmgr -b 0000 -B           # MokManager のエントリを削除 (番号は表示に合わせる)
mokutil --list-enrolled | grep "Subject: CN=DKMS"
/sbin/modinfo -F signer zfs nvidia-current     # DKMS module signing key
sudo rm /boot/efi/dkms-mok.cer
```

## 未検証の案

| 案 | 内容 | リスク |
| --- | --- | --- |
| BIOSの再書き込み | 公式の4301を、EZ Flash (BIOSの `Tool`) でもう一度書き、NVRAM領域を整える | 書き込み中の電源断で起動不能。CrashFree BIOSでの復旧が前提 |
| PCIeカードを外す | Emulex SFP+ などを外した最小構成で、CSMを `Disabled` にする | `B7` なら、そのたびにCMOSクリア (MOKも消える) |
| Valorant用に別のPCを使う | このサーバーはDebian専用のまま | なし |
