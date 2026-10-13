#!/usr/bin/env bash
# Idle状態が一定時間続いた場合のみ systemctl suspend を実行する。
#
# Suspendを止める条件 (どれか1つでも該当すれば「アクティブ」):
#   - 確立済みのSSH接続がある (Mac→サーバー、サーバー→コンテナ(ProxyJump経由のZed)を含む)
#   - systemd-inhibit で sleep を block しているジョブがある
#
# 長時間ジョブ (build, CI, render, encode, AI, backup) は、サーバー上で次のように
# 自身をラップしてSuspendを止める:
#   systemd-inhibit --what=sleep --mode=block --who=<name> --why=<reason> <command>
# ※ コンテナ内のジョブはホストのinhibitorを持てないため、コンテナ内でSSHセッション
#   (tmux等を含む接続)を張っておくか、ホスト側でラップすること。
#
# 環境変数: DEV_IDLE_TIMEOUT (秒, 既定3600) / DEV_AUTO_SUSPEND_DRY_RUN=1 (判定だけ表示)
set -euo pipefail

IDLE_TIMEOUT="${DEV_IDLE_TIMEOUT:-3600}"
STATE_FILE="${DEV_AUTO_SUSPEND_STATE:-/run/dev-auto-suspend.last-active}"
DRY_RUN="${DEV_AUTO_SUSPEND_DRY_RUN:-0}"

has_ssh_sessions() {
  ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | tail -n +2 | grep -q .
}

# --list は mode での絞り込みができないため、最終列(MODE)が block かつ WHAT に sleep を含む行だけを見る
has_sleep_inhibitors() {
  systemd-inhibit --list --no-pager --no-legend 2>/dev/null | awk '$NF == "block" && /sleep/ { found = 1 } END { exit !found }'
}

say() { [ "$DRY_RUN" = 1 ] && echo "[dry-run] $*" || true; }

now="$(date +%s)"

if has_ssh_sessions; then
  say "active: ssh session"; echo "$now" > "$STATE_FILE"; exit 0
fi
if has_sleep_inhibitors; then
  say "active: sleep inhibitor"; echo "$now" > "$STATE_FILE"; exit 0
fi

if [ ! -f "$STATE_FILE" ]; then
  say "no state file; starting idle timer"; echo "$now" > "$STATE_FILE"; exit 0
fi

last_active="$(cat "$STATE_FILE")"
idle_for=$((now - last_active))

if [ "$idle_for" -lt "$IDLE_TIMEOUT" ]; then
  say "idle ${idle_for}s < ${IDLE_TIMEOUT}s; not yet"; exit 0
fi

if [ "$DRY_RUN" = 1 ]; then
  say "idle ${idle_for}s >= ${IDLE_TIMEOUT}s; WOULD suspend"; exit 0
fi

logger -t dev-auto-suspend "idle for ${idle_for}s, suspending"
# 復帰後のタイマー仕切り直しは shell/sleep-hook (systemd-sleepのpostフック) が行う
systemctl suspend
