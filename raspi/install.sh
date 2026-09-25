#!/usr/bin/env bash
# Raspberry Piへ dev-server-wake をインストールする。
# Usage: raspi/install.sh <raspi-ssh-host>
set -euo pipefail

host="${1:?usage: install.sh <raspi-ssh-host>}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

scp "$DIR/wol/dev-server-wake" "$host:/tmp/dev-server-wake"
ssh "$host" 'sudo install -m 755 /tmp/dev-server-wake /usr/local/bin/dev-server-wake && rm /tmp/dev-server-wake'

echo "installed: /usr/local/bin/dev-server-wake on $host"
echo "note: wakeonlan (or etherwake) must be installed on $host"
