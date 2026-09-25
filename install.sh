#!/usr/bin/env bash
# 各ホストの役割ごとにセットアップスクリプトを振り分けるだけのdispatcher。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: install.sh <macos|server|raspi> [args...]

  macos            MacBook (Thin Client) をセットアップする
  server           Development Server (Debian) をセットアップする
  raspi <host>     指定したRaspberry PiにWake Gatewayをインストールする
EOF
}

target="${1:-}"
[ -n "$target" ] && shift || true

case "$target" in
  macos)  exec "$DIR/macos/install.sh" "$@" ;;
  server) exec "$DIR/server/install.sh" "$@" ;;
  raspi)  exec "$DIR/raspi/install.sh" "$@" ;;
  *) usage; exit 1 ;;
esac
