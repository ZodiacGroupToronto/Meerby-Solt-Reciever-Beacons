#!/usr/bin/env bash
set -euo pipefail

# Create a password-protected 7z archive of the repository and move it to ../public_html
# Usage:
#  - Set env var `ARCHIVE_PASS` to the desired password, or run interactively and you'll be prompted.
#  - Optionally pass a custom target directory as the first argument.
# Example:
#  ARCHIVE_PASS=MySecret ./deploy/scripts/pack_and_move.sh
#  ./deploy/scripts/pack_and_move.sh /var/www/public_html

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# script is in deploy/scripts -> repo root is two levels up
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_BASE="$(basename "$REPO_ROOT")"
PARENT_DIR="$(dirname "$REPO_ROOT")"

# Default target directory: ../public_html relative to the repo root
TARGET_DIR="${1:-$PARENT_DIR/public_html}"

# Password can be provided via env var ARCHIVE_PASS
PASS="${ARCHIVE_PASS:-}"

if [ -z "$PASS" ]; then
  if [ -t 0 ]; then
    read -s -p "Archive password (will not echo): " PASS
    echo
  else
    echo "No password provided via ARCHIVE_PASS and not running interactively. Exiting." >&2
    exit 1
  fi
fi

ARCHIVE_NAME="${REPO_BASE}-${TIMESTAMP}.7z"

echo "[pack_and_move] Repo root: $REPO_ROOT"
echo "[pack_and_move] Parent dir: $PARENT_DIR"
echo "[pack_and_move] Archive: $ARCHIVE_NAME"
echo "[pack_and_move] Excluding: $REPO_BASE/venv and $REPO_BASE/deploy"

# Create the archive from the parent directory so the archive contains the repo folder
cd "$PARENT_DIR"

echo "[pack_and_move] Running 7z..."
# Use -mhe=on to encrypt headers, -p to set password, -xr! to exclude directories
7z a -t7z "$ARCHIVE_NAME" "$REPO_BASE" -p"$PASS" -mhe=on -xr!"$REPO_BASE/venv" -xr!"$REPO_BASE/deploy"

echo "[pack_and_move] Creating target dir: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

echo "[pack_and_move] Moving archive to target dir..."
mv "$ARCHIVE_NAME" "$TARGET_DIR/"

echo "[pack_and_move] Archive moved to $TARGET_DIR/$ARCHIVE_NAME"

exit 0
