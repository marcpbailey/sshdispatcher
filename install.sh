#!/bin/bash
# Idempotent installer for sshdispatcher.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="/usr/local/bin"
MAN_DIR="/usr/local/share/man/man1"
PUTTY_SESSION_DIR="${HOME}/.putty/sessions"

echo "==> Creating directories if needed..."
sudo mkdir -p "$BIN_DIR" "$MAN_DIR"
mkdir -p "$PUTTY_SESSION_DIR"

echo "==> Symlinking sshdispatcher -> $BIN_DIR/sshdispatcher"
sudo ln -sf "$REPO_DIR/sshdispatcher" "$BIN_DIR/sshdispatcher"

echo "==> Symlinking sshdispatcher.1 -> $MAN_DIR/sshdispatcher.1"
sudo ln -sf "$REPO_DIR/sshdispatcher.1" "$MAN_DIR/sshdispatcher.1"

echo "==> Symlinking sshdispatcher.putty -> $PUTTY_SESSION_DIR/sshdispatcher.putty"
ln -sf "$REPO_DIR/sshdispatcher.putty" "$PUTTY_SESSION_DIR/sshdispatcher.putty"

if ! command -v plink &>/dev/null; then
  echo ""
  echo "WARNING: plink not found in PATH."
  echo "         Install it with: brew install putty"
fi

echo ""
echo "Installation complete. Next steps:"
echo ""
echo "  1. Add to ~/.zshrc:"
echo "       alias ssh=sshdispatcher"
echo ""
echo "  2. Confirm /usr/local/bin is in your PATH:"
printf "       echo \$PATH | tr ':' '\\\\n' | grep /usr/local/bin\\n"
echo ""
echo "  3. Convert any switch keys to PuTTY format (one-time):"
echo "       puttygen ~/.ssh/switch_key -O private -o ~/.ssh/switch_key.ppk"
