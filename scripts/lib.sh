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

# config/projects.conf から target を検索し "host path instance repo vcs deps studio" を1行で出力する。
# instance/repo/deps/studio列が無い行は "-"、vcs列が無い行は "git" を返す。見つからない場合は何も出力せず終了コード1。
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
      deps = (NF >= 7) ? $7 : "-"
      studio = (NF >= 8) ? $8 : "-"
      print $2, $3, inst, repo, vcs, deps, studio
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

# リモートホストのポートへ、SSHトンネルを張る (同じホスト・ポート宛ての生存中のトンネルがあれば再利用する)。
# 張ったローカルポートを標準出力に出す。失敗したときは何も出さず、終了コード1。
#   Usage: ensure_tunnel <ssh-host> <remote-port> <first-local-port> <ttl-seconds>
#   トンネルはSSH接続なので、開いている間はサーバーの自動Suspendを止める。寿命 (ttl) で自動的に閉じる。
ensure_tunnel() {
  local host="$1" remote_port="$2" first_port="$3" ttl="$4"
  local state_dir="$HOME/.config/dev/tunnels" state sp spid port="" p pid
  mkdir -p "$state_dir"; state="$state_dir/$host-$remote_port"
  if [ -f "$state" ]; then
    read -r sp spid < "$state" || true
    if [ -n "${spid:-}" ] && ps -p "$spid" -o args= 2>/dev/null | grep -q -- "-L ${sp}:127.0.0.1:${remote_port}.* ${host} "; then
      echo "$sp"; return 0
    fi
  fi
  for p in $(seq "$first_port" $((first_port + 9))); do
    if ! nc -z 127.0.0.1 "$p" 2>/dev/null; then port="$p"; break; fi
  done
  [ -n "$port" ] || { err "空いているローカルポートがありません ($first_port-$((first_port + 9)))"; return 1; }
  ssh -f -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ExitOnForwardFailure=yes \
      -L "${port}:127.0.0.1:${remote_port}" "$host" "sleep $ttl" </dev/null >/dev/null 2>&1 \
    || { err "SSHトンネルを張れませんでした"; return 1; }
  pid="$(pgrep -nf "ssh .*-L ${port}:127.0.0.1:${remote_port}.* ${host} " || true)"
  echo "$port ${pid:-0}" > "$state"
  echo "$port"
}
