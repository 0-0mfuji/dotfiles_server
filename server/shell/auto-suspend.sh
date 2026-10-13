#!/usr/bin/env bash
# Idle状態が一定時間続いた場合のみ systemctl suspend を実行する。
#
# Suspendを止める条件 (どれか1つでも該当すれば「アクティブ」):
#   - 確立済みのSSH接続がある (Mac→サーバー、サーバー→コンテナ(ProxyJump経由のZed)を含む)
#   - systemd-inhibit で sleep を block しているジョブがある
#   - コンテナ内を含むAIエージェント (claude / codex / dsh) のプロセスが、直近の実行間隔でCPUを使っている
#     (プロンプトを開いたまま放置、常駐するWeb UIの待機は、CPUをほぼ使わないので「アクティブ」にならない)
#   - GPUが計算中 (nvidia-smi の使用率が閾値以上)。コンテナ内のPython (学習など) も、ホストから見える。
#     VRAMを持っているだけで使用率が0の放置ノートブックは「アクティブ」にならない。複数のGPUは、どれか1つでよい。
#
# 長時間ジョブ (build, CI, render, encode, AI, backup) は、サーバー上で次のように
# 自身をラップしてSuspendを止める:
#   systemd-inhibit --what=sleep --mode=block --who=<name> --why=<reason> <command>
# ※ コンテナ内のジョブはホストのinhibitorを持てないため、コンテナ内でSSHセッション
#   (tmux等を含む接続)を張っておくか、ホスト側でラップすること。
#
# 環境変数: DEV_IDLE_TIMEOUT (秒, 既定3600) / DEV_AUTO_SUSPEND_DRY_RUN=1 (判定だけ表示)
#   DEV_KEEP_AWAKE_PROCS     対象プロセスのコマンドラインに一致する拡張正規表現
#   DEV_KEEP_AWAKE_CPU_TICKS 1回の実行間隔で、これ以上CPUを使えば「アクティブ」 (既定100 = 約1秒分)
#   DEV_KEEP_AWAKE_GPU_UTIL  GPU使用率(%)がこれ以上なら「アクティブ」 (既定5)。DEV_GPU_SAMPLES回(既定3)、1秒おきに見る
set -euo pipefail

IDLE_TIMEOUT="${DEV_IDLE_TIMEOUT:-3600}"
STATE_FILE="${DEV_AUTO_SUSPEND_STATE:-/run/dev-auto-suspend.last-active}"
DRY_RUN="${DEV_AUTO_SUSPEND_DRY_RUN:-0}"
PROC="${DEV_PROC_ROOT:-/proc}"
AGENT_RE="${DEV_KEEP_AWAKE_PROCS:-(^|/)claude( |\$)|(^|/)codex( |\$)|bin\.ts web}"
CPU_THRESHOLD="${DEV_KEEP_AWAKE_CPU_TICKS:-100}"
CPU_STATE="${DEV_AUTO_SUSPEND_CPU_STATE:-/run/dev-auto-suspend.cpu}"
NVIDIA_SMI="${DEV_NVIDIA_SMI:-nvidia-smi}"
GPU_UTIL_THRESHOLD="${DEV_KEEP_AWAKE_GPU_UTIL:-5}"
GPU_SAMPLES="${DEV_GPU_SAMPLES:-3}"

has_ssh_sessions() {
  ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | tail -n +2 | grep -q .
}

# --list は mode での絞り込みができないため、最終列(MODE)が block かつ WHAT に sleep を含む行だけを見る
has_sleep_inhibitors() {
  systemd-inhibit --list --no-pager --no-legend 2>/dev/null | awk '$NF == "block" && /sleep/ { found = 1 } END { exit !found }'
}

# 対象プロセスのCPU時間 (utime+stime+子の分) が、前回の実行から何ticks増えたかを返す。
# 前回の記録が無いとき(起動直後など)は "-" を返し、アクティブとは見なさない。
# プロセスはpid+起動時刻で識別する。新しく起動したプロセスは、その時点までのCPU時間を増分とみなす。
# コンテナ内のプロセスも、ホストの /proc からそのまま見える。
agent_cpu_delta() {
  local cur d comm cmd fields
  cur="$(mktemp)"
  for d in "$PROC"/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    comm="$(cat "$d/comm" 2>/dev/null || true)"
    case "$comm" in grep|egrep|sed|awk|tr|pgrep|bash|sh|dash|ssh|sshd|sudo) continue ;; esac
    cmd="$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null || true)"
    [ -n "$cmd" ] || continue
    printf '%s' "$cmd" | grep -Eq -- "$AGENT_RE" || continue
    fields="$(sed 's/^.*) //' "$d/stat" 2>/dev/null | awk '{print $20, $12+$13+$14+$15}')" || continue
    [ -n "$fields" ] && echo "${d##*/} $fields" >> "$cur"
  done
  touch "$cur"
  if [ ! -f "$CPU_STATE" ]; then mv "$cur" "$CPU_STATE"; echo "-"; return; fi
  awk 'NR==FNR { p[$1" "$2]=$3; next } { k=$1" "$2; d=$3-((k in p)?p[k]:0); if (d<0) d=0; s+=d } END { print s+0 }' "$CPU_STATE" "$cur"
  mv "$cur" "$CPU_STATE"
}

# どれかのGPUの使用率が閾値以上なら成功 (0)。瞬間値だと取りこぼすので、数回、間をおいて見る。
# nvidia-smi が無い・失敗するとき (ドライバ未導入、GPU無し) は、「アクティブではない」とする。
has_gpu_activity() {
  command -v "$NVIDIA_SMI" >/dev/null 2>&1 || return 1
  local i
  for ((i = 0; i < GPU_SAMPLES; i++)); do
    "$NVIDIA_SMI" --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null \
      | awk -v t="$GPU_UTIL_THRESHOLD" '$1 + 0 >= t { found = 1 } END { exit !found }' && return 0
    [ "$i" -lt $((GPU_SAMPLES - 1)) ] && sleep 1
  done
  return 1
}

say() { [ "$DRY_RUN" = 1 ] && echo "[dry-run] $*" || true; }

now="$(date +%s)"
agent_delta="$(agent_cpu_delta)"

if has_ssh_sessions; then
  say "active: ssh session"; echo "$now" > "$STATE_FILE"; exit 0
fi
if has_sleep_inhibitors; then
  say "active: sleep inhibitor"; echo "$now" > "$STATE_FILE"; exit 0
fi

if [ "$agent_delta" != "-" ] && [ "$agent_delta" -ge "$CPU_THRESHOLD" ]; then
  say "active: agent activity (+${agent_delta} ticks)"; echo "$now" > "$STATE_FILE"; exit 0
fi

if has_gpu_activity; then
  say "active: gpu busy"; echo "$now" > "$STATE_FILE"; exit 0
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
