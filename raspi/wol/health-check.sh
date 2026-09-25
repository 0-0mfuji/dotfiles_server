#!/usr/bin/env bash
# Development Serverの死活状態を定期的にログへ記録する (任意・cron等で使用)。
# Usage: health-check.sh <target-host-or-ip> [log-file]
set -euo pipefail

target="${1:?usage: health-check.sh <target-host-or-ip> [log-file]}"
log_file="${2:-/var/log/dev-server-health.log}"

ts="$(date -Iseconds)"
if ping -c1 -W2 "$target" >/dev/null 2>&1; then
  echo "$ts up" >> "$log_file"
else
  echo "$ts down" >> "$log_file"
fi
