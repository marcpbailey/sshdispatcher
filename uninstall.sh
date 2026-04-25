#!/bin/bash
# Remove sshdispatcher symlinks from /usr/local.
set -euo pipefail

BIN_DIR="/usr/local/bin"
MAN_DIR="/usr/local/share/man/man1"

echo "==> Removing $BIN_DIR/sshdispatcher"
sudo rm -f "$BIN_DIR/sshdispatcher"

echo "==> Removing $MAN_DIR/sshdispatcher.1"
sudo rm -f "$MAN_DIR/sshdispatcher.1"

echo ""
echo "Uninstall complete."
echo "Remember to remove 'alias ssh=sshdispatcher' from ~/.zshrc."
