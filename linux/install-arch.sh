#!/usr/bin/env bash
# Arch Linux client setup for remote development.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="$DIR/macos"

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then return; fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "skip (exists, not a symlink): $dst"
    return
  fi
  ln -sfn "$src" "$dst"
  echo "linked: $dst -> $src"
}

for command_name in bash git ssh ssh-add ssh-agent python3 seq nc pgrep; do
  command -v "$command_name" >/dev/null || {
    echo "error: $command_name is required (install with pacman)" >&2
    exit 1
  }
done

mkdir -p "$HOME/.local/bin" "$HOME/.ssh/config.d" "$HOME/.ssh/sockets"
chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets"
link "$MACOS_DIR/bin/dev" "$HOME/.local/bin/dev"
link "$MACOS_DIR/ssh/config" "$HOME/.ssh/config.d/dotfiles"
touch "$HOME/.ssh/config.local"

SSHCONFIG="$HOME/.ssh/config"
if [ -L "$SSHCONFIG" ]; then
  if ! grep -qF 'Include ~/.ssh/config.d/dotfiles' "$SSHCONFIG"; then
    echo "note: add these lines at the top of $SSHCONFIG:"
    echo '  Include ~/.ssh/config.d/dotfiles'
    echo '  Include ~/.ssh/config.local'
  fi
else
  touch "$SSHCONFIG"
  chmod 600 "$SSHCONFIG"
  if ! grep -qF 'Include ~/.ssh/config.d/dotfiles' "$SSHCONFIG"; then
    { echo 'Include ~/.ssh/config.d/dotfiles'; echo 'Include ~/.ssh/config.local'; cat "$SSHCONFIG"; } > "$SSHCONFIG.tmp"
    mv "$SSHCONFIG.tmp" "$SSHCONFIG"
    chmod 600 "$SSHCONFIG"
    echo "updated: $SSHCONFIG (added Include)"
  fi
fi

mkdir -p "$HOME/.config/dev"
if [ ! -f "$HOME/.config/dev/local.env" ]; then
  cp "$DIR/config/local.env.example" "$HOME/.config/dev/local.env"
  echo "created: $HOME/.config/dev/local.env (edit machine-specific values)"
fi

echo
echo 'Arch Linux client setup is ready. Install Zed and Tailscale separately, then configure:'
echo "  $HOME/.ssh/config.local"
echo "  $HOME/.config/dev/local.env"
echo 'Add ~/.local/bin to PATH if needed.'
