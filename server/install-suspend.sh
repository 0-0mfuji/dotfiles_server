#!/usr/bin/env bash
# 自動Suspend (systemd timer) を導入する。root権限が必要。
# Usage: sudo ./install-suspend.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run with sudo: sudo $0" >&2; exit 1; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 755 "$DIR/shell/auto-suspend.sh" /usr/local/bin/dev-auto-suspend.sh
install -m 755 "$DIR/shell/sleep-hook" /usr/lib/systemd/system-sleep/dev-auto-suspend
install -m 644 "$DIR/systemd/dev-auto-suspend.service" /etc/systemd/system/
install -m 644 "$DIR/systemd/dev-auto-suspend.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now dev-auto-suspend.timer

systemctl list-timers dev-auto-suspend.timer --no-pager
echo "installed. idle timeout: ${DEV_IDLE_TIMEOUT:-3600}s (change via /etc/default/dev-auto-suspend)"
