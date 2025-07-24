#!/usr/bin/env bash
# restore_configs.sh – restore backed-up config files to their default locations

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-d backup_directory] [-h]

  -d  Directory containing backup files (default: /backups)
  -h  Show this help message
EOF
}

# Default backup directory
BACKUP_DIR="/backups"

# Parse options
while getopts "d:h" opt; do
  case $opt in
    d) BACKUP_DIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# Must run as root
if (( EUID != 0 )); then
  echo "ERROR: This script must be run as root." >&2
  exit 1
fi

# Map of filename → destination path
declare -A file_map=(
  ["krb5.conf"]="/etc/krb5.conf"
  ["nsswitch.conf"]="/etc/nsswitch.conf"
  ["access.conf"]="/etc/security/access.conf"
  ["pam_winbind.conf"]="/etc/pam_winbind.conf"
)

echo "Restoring configs from backup dir: $BACKUP_DIR"
for filename in "${!file_map[@]}"; do
  SRC="$BACKUP_DIR/$filename"
  DEST="${file_map[$filename]}"

  if [[ ! -f "$SRC" ]]; then
    echo "Warning: backup file not found: $SRC" >&2
    continue
  fi

  # Ensure destination directory exists
  mkdir -p "$(dirname "$DEST")"

  # Copy, preserving mode/ownership
  echo "  → $SRC → $DEST"
  cp -a "$SRC" "$DEST"
done

echo "Restore complete."
