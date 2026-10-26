#!/usr/bin/env bash
# GRUBに「Windows」(ESPの bootmgfw.efi をchainload) を追加し、
# `boot-windows` (grub-reboot) で次回1回だけWindowsを起動できるようにする。
#
# 前提: WindowsのブートファイルがESP (/boot/efi) にあること (docs/windows.md の手順1)。
# 実行: sudo ./server/grub/setup-windows.sh
#
# 何度実行しても同じ結果になる。変更前に /etc/default/grub, /etc/grub.d/40_custom,
# /boot/grub/grub.cfg をバックアップし、生成後の grub.cfg を grub-script-check で検証する。
set -euo pipefail

ESP_MOUNT="${ESP_MOUNT:-/boot/efi}"
BOOTMGR="$ESP_MOUNT/EFI/Microsoft/Boot/bootmgfw.efi"
ENTRY_ID="windows"
STAMP="$(date +%Y%m%d-%H%M%S)"

die() { echo "error: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "root で実行してください: sudo $0"
[ -f "$BOOTMGR" ] || die "Windowsのブートファイルがありません: $BOOTMGR (docs/windows.md の手順1を先に実施)"

# ESPのUUIDは機器固有なので、マウント中のESPから取得する
ESP_DEV="$(findmnt -no SOURCE "$ESP_MOUNT")" || die "$ESP_MOUNT がマウントされていません"
ESP_UUID="$(lsblk -no UUID "$ESP_DEV" | head -1)"
[ -n "$ESP_UUID" ] || die "ESP ($ESP_DEV) のUUIDを取得できません"
echo "ESP: $ESP_DEV (UUID=$ESP_UUID)"

echo "== バックアップ ($STAMP)"
cp -a /etc/default/grub "/etc/default/grub.bak.$STAMP"
cp -a /etc/grub.d/40_custom "/etc/grub.d/40_custom.bak.$STAMP"
cp -a /boot/grub/grub.cfg "/boot/grub/grub.cfg.bak.$STAMP"

echo "== /etc/default/grub: GRUB_DEFAULT=saved, os-prober無効"
# saved: grub-reboot の「次回だけ」と、既定 (saved_entry) を分けて持てる。
# os-prober無効: 40_custom の Windows と重複して検出されるのを避ける。
sed -i -E 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
  sed -i -E 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=true/' /etc/default/grub
else
  echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub
fi

echo "== /etc/grub.d/40_custom: Windows エントリ"
if grep -q -- "--id $ENTRY_ID" /etc/grub.d/40_custom; then
  echo "(既にあります。UUIDだけ更新)"
  sed -i -E "s/(--fs-uuid --set=root )[0-9A-Fa-f-]+/\1$ESP_UUID/" /etc/grub.d/40_custom
else
  cat >> /etc/grub.d/40_custom <<EOF

menuentry "Windows" --id $ENTRY_ID {
    insmod part_gpt
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root $ESP_UUID
    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
EOF
fi

echo "== update-grub"
update-grub

echo "== 構文チェック"
grub-script-check /boot/grub/grub.cfg
grep -q -- "--id $ENTRY_ID" /boot/grub/grub.cfg || die "grub.cfg に $ENTRY_ID エントリがありません"

echo "== 既定を先頭 (Debian) に固定"
grub-set-default 0
grub-editenv list

echo
echo "== メニュー項目"
grep -E '^(menuentry|submenu) ' /boot/grub/grub.cfg | cut -c1-80
echo
echo "done. 次回だけWindowsで起動するには: boot-windows"
