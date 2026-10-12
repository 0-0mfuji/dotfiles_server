#!/usr/bin/env bash
# Development Server (Debian) 側のセットアップ。
# Incus環境自体の構築は別リポジトリの責務であり、ここでは触れない。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

link "$DIR/shell/profile.sh" "$HOME/.config/dev-server-profile.sh"
grep -qF "dev-server-profile.sh" "$HOME/.profile" 2>/dev/null || \
  echo '[ -f "$HOME/.config/dev-server-profile.sh" ] && . "$HOME/.config/dev-server-profile.sh"' >> "$HOME/.profile"

link "$DIR/git/gitconfig" "$HOME/.config/git/dotfiles-server.gitconfig"
git config --global --get-all include.path 2>/dev/null | grep -qF "dotfiles-server.gitconfig" || \
  git config --global --add include.path "$HOME/.config/git/dotfiles-server.gitconfig"

echo ""
echo "auto-suspend (systemd) を有効にするには、sudo権限で次を実行してください:"
echo "  sudo $DIR/install-suspend.sh"
echo ""
echo "done."
