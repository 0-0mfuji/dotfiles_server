#!/usr/bin/env bash
# Idle状態が一定時間続いた場合のみ systemctl suspend を実行する。
#
# 長時間ジョブ(LLVM build, CI, Blender render, video encode, AI workload,
# backup等)は各ジョブ側が `systemd-inhibit --what=sleep --mode=block ...`
# で自身をラップし、Suspendをブロックする設計とする。このスクリプトは
# その有無とSSHセッションの有無だけを見る。
set -euo pipefail

IDLE_TIMEOUT="${DEV_IDLE_TIMEOUT:-3600}"
STATE_FILE="/run/dev-auto-suspend.last-active"

has_ssh_sessions() {
  ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | grep -q .
}

has_sleep_inhibitors() {
  systemd-inhibit --list --mode=block 2>/dev/null | grep -q 'sleep'
}

now="$(date +%s)"

if has_ssh_sessions || has_sleep_inhibitors; then
  echo "$now" > "$STATE_FILE"
  exit 0
fi

if [ ! -f "$STATE_FILE" ]; then
  echo "$now" > "$STATE_FILE"
  exit 0
fi

last_active="$(cat "$STATE_FILE")"
idle_for=$((now - last_active))

if [ "$idle_for" -ge "$IDLE_TIMEOUT" ]; then
  logger -t dev-auto-suspend "idle for ${idle_for}s, suspending"
  systemctl suspend
  date +%s > "$STATE_FILE"
fi
