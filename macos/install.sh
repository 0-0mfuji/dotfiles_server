#!/usr/bin/env bash
# MacBook (Thin Client) 側のセットアップ。
# シンボリックリンクを張るだけで、既存ファイルは上書きしない。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="$DIR/macos"

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "skip (exists, not a symlink): $dst"
    return
  fi
  ln -sfn "$src" "$dst"
  echo "linked: $dst -> $src"
}

mkdir -p "$HOME/.local/bin"
link "$MACOS_DIR/bin/dev" "$HOME/.local/bin/dev"

mkdir -p "$HOME/.ssh/config.d" "$HOME/.ssh/sockets"
chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets"
link "$MACOS_DIR/ssh/config" "$HOME/.ssh/config.d/dotfiles"
touch "$HOME/.ssh/config.local"

mkdir -p "$HOME/.config/zsh"
link "$MACOS_DIR/zsh/zshrc.dev" "$HOME/.config/zsh/dotfiles-dev.zsh"

ZSHRC="$HOME/.zshrc"
MARK="# >>> dotfiles (dev) >>>"
touch "$ZSHRC"
if ! grep -qF "$MARK" "$ZSHRC"; then
  {
    echo ""
    echo "$MARK"
    echo "source \"$HOME/.config/zsh/dotfiles-dev.zsh\""
    echo "# <<< dotfiles (dev) <<<"
  } >> "$ZSHRC"
  echo "updated: $ZSHRC"
fi

# Include はマッチした時点でそれ以降のHost定義に影響するため先頭に置く
SSHCONFIG="$HOME/.ssh/config"
if [ -L "$SSHCONFIG" ]; then
  # 別のdotfilesが管理するシンボリックリンクを壊さないよう、自動編集しない
  if ! grep -qF "Include ~/.ssh/config.d/dotfiles" "$SSHCONFIG"; then
    echo "note: $SSHCONFIG is a symlink ($(readlink "$SSHCONFIG")); add these lines at its top yourself:"
    echo "  Include ~/.ssh/config.d/dotfiles"
    echo "  Include ~/.ssh/config.local"
  fi
else
touch "$SSHCONFIG"
chmod 600 "$SSHCONFIG"
if ! grep -qF "Include ~/.ssh/config.d/dotfiles" "$SSHCONFIG"; then
  { echo "Include ~/.ssh/config.d/dotfiles"; echo "Include ~/.ssh/config.local"; cat "$SSHCONFIG"; } > "$SSHCONFIG.tmp"
  mv "$SSHCONFIG.tmp" "$SSHCONFIG"
  echo "updated: $SSHCONFIG (added Include)"
fi
fi

mkdir -p "$HOME/.config/dev"
if [ ! -f "$HOME/.config/dev/local.env" ]; then
  cp "$DIR/config/local.env.example" "$HOME/.config/dev/local.env"
  echo "created: $HOME/.config/dev/local.env (edit this file with your machine-specific values)"
fi

echo ""
echo "done. Make sure \$HOME/.local/bin is in your PATH, then edit:"
echo "  - $HOME/.ssh/config.local        (実際のHost定義)"
echo "  - $HOME/.config/dev/local.env    (DEV_SERVER_HOST / DEV_SERVER_MAC / RASPI_HOST)"
