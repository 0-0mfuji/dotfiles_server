#!/usr/bin/env bash
# scripts/lib.sh - dev コマンド群で共有するヘルパー関数
# 単体では実行せず、他のスクリプトから source して使う。

log() { printf '\033[1;34m[dev]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[dev]\033[0m %s\n' "$*" >&2; }

# ~/.config/dev/local.env (Git管理外・マシン固有) を読み込む
load_local_env() {
  local env_file="${DEV_LOCAL_ENV:-$HOME/.config/dev/local.env}"
  if [ -f "$env_file" ]; then
    # shellcheck disable=SC1090
    source "$env_file"
  fi
}

# config/projects.conf から target を検索し "host path instance repo" を1行で出力する。
# instance/repo列が無い行は "-" を返す。見つからない場合は何も出力せず終了コード1。
lookup_target() {
  local target="$1"
  local conf="${DEV_PROJECTS_CONF:-$REPO_ROOT/config/projects.conf}"
  [ -f "$conf" ] || { err "config not found: $conf"; return 1; }

  awk -v t="$target" '
    /^[[:space:]]*#/ { next }
    NF == 0 { next }
    $1 == t {
      inst = (NF >= 4) ? $4 : "-"
      repo = (NF >= 5) ? $5 : "-"
      print $2, $3, inst, repo
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$conf"
}
