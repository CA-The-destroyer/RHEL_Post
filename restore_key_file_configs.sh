#!/usr/bin/env bash
# restore_configs.sh – restore backed-up config files to standard locations,
# run dos2unix, and set permissions (sudoers.d file validated via visudo)

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-d backup_directory] [-h]

  -d  Directory containing backup files (default: /backups)
  -h  Show this help message
EOF
}

BACKUP_DIR="/backups"

while getopts "d:h" opt; do
  case $opt in
    d) BACKUP_DIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# Root required
if (( EUID != 0 )); then
  echo "ERROR: This script must be run as root." >&2
  exit 1
fi

# deps
if ! command -v dos2unix &>/dev/null; then
  echo "ERROR: dos2unix not found. Install it (e.g. dnf install dos2unix) before running." >&2
  exit 1
fi

# filename -> destination
declare -A file_map=(
  ["krb5.conf"]="/etc/krb5.conf"
  ["nsswitch.conf"]="/etc/nsswitch.conf"
  ["access.conf"]="/etc/security/access.conf"
  ["pam_winbind.conf"]="/etc/security/pam_winbind.conf"
  ["ctxfas"]="/etc/pam.d/ctxfas"
  ["smb.conf"]="/etc/samba/smb.conf"
  ["support"]="/etc/sudoers.d/support"
)

echo "Restoring configs from: $BACKUP_DIR"
for filename in "${!file_map[@]}"; do
  SRC="$BACKUP_DIR/$filename"
  DEST="${file_map[$filename]}"

  if [[ ! -f "$SRC" ]]; then
    echo "Warning: missing backup file: $SRC" >&2
    continue
  fi

  mkdir -p "$(dirname "$DEST")"

  if [[ "$filename" == "support" ]]; then
    # Handle sudoers drop-in safely
    if ! command -v visudo &>/dev/null; then
      echo "ERROR: visudo not found; cannot validate /etc/sudoers.d/support. Aborting." >&2
      exit 1
    fi

    TMP="${DEST}.tmp.$$"
    cp -a "$SRC" "$TMP"
    dos2unix "$TMP" &>/dev/null

    if visudo -cf "$TMP" &>/dev/null; then
      # Enforce root:root and 0440 as required by sudoers
      install -o root -g root -m 0440 "$TMP" "$DEST"
      rm -f "$TMP"
      echo "  ✓ sudoers validated and installed: $DEST (mode 0440)"
    else
      echo "ERROR: visudo syntax check FAILED for $SRC. Not installing." >&2
      rm -f "$TMP"
      continue
    fi

  else
    # Regular configs: copy, normalize, and a+rx as requested
    echo "  → $SRC → $DEST"
    cp -a "$SRC" "$DEST"
    dos2unix "$DEST" &>/dev/null
    chmod a+rx "$DEST"
  fi
done

echo "Restore complete."
