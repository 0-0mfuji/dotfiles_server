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

# config/projects.conf から target を検索し "host path instance repo vcs" を1行で出力する。
# instance/repo列が無い行は "-"、vcs列が無い行は "git" を返す。見つからない場合は何も出力せず終了コード1。
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
      vcs  = (NF >= 6) ? $6 : "git"
      print $2, $3, inst, repo, vcs
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$conf"
}

# projects.conf の target列 (キー) を、書かれた順に出力する。
list_targets() {
  local conf="${DEV_PROJECTS_CONF:-$REPO_ROOT/config/projects.conf}"
  awk '/^[[:space:]]*#/ { next } NF == 0 { next } { print $1 }' "$conf"
}

# "dev <target> [project]" の指定から、projects.conf のキーを1つに決めて出力する。
#   dev os sota  -> os/sota
#   dev os       -> os/ で始まるキーが1つならそれ。複数なら、対話できればメニュー、できなければ先頭
#   dev lang     -> キー lang がそのまま存在すれば、それ (今までの書き方)
resolve_target() {
  local t="$1" p="${2:-}" key k n i ans
  local keys=()

  if [ -n "$p" ]; then
    key="$t/$p"
    if list_targets | grep -qxF -- "$key"; then echo "$key"; return 0; fi
    err "unknown project: $t $p"
    return 1
  fi

  if list_targets | grep -qxF -- "$t"; then echo "$t"; return 0; fi

  while IFS= read -r k; do keys+=("$k"); done < <(list_targets | awk -v g="$t/" 'index($0, g) == 1')
  n=${#keys[@]}
  if [ "$n" -eq 0 ]; then err "unknown target: $t"; return 1; fi
  if [ "$n" -eq 1 ]; then echo "${keys[0]}"; return 0; fi

  if [ -t 0 ] && [ -t 2 ]; then
    {
      echo "[dev] $t のプロジェクトを選んでください:"
      i=1
      for k in "${keys[@]}"; do
        printf '  %d) %s\n' "$i" "${k#*/}"
        i=$((i + 1))
      done
      printf '番号 [1]: '
    } >&2
    read -r ans < /dev/tty || ans=""
    ans="${ans:-1}"
    case "$ans" in
      ''|*[!0-9]*) err "番号を入力してください"; return 1 ;;
    esac
    if [ "$ans" -lt 1 ] || [ "$ans" -gt "$n" ]; then err "選択肢の範囲外です: $ans"; return 1; fi
    echo "${keys[$((ans - 1))]}"
  else
    echo "${keys[0]}"
  fi
}
