#!/usr/bin/env bash

declare -A files=(
  ["krb5.conf"]="/etc/krb5.conf"
  ["nsswitch.conf"]="/etc/nsswitch.conf"
  ["access.conf"]="/etc/security/access.conf"
  ["pam_winbind.conf"]="/etc/pam_winbind.conf"
)

# If you supply a number here, any file older than N days (mtime) will be flagged.
# Usage: ./check-files.sh [max_age_in_days]
MAX_AGE_DAYS=${1:-0}

exit_code=0

for name in "${!files[@]}"; do
  path="${files[$name]}"

  if [[ ! -e "$path" ]]; then
    echo "FAIL: $name → $path (not found)" >&2
    exit_code=1
    continue
  fi

  # stat: %y = modify time, %z = change time
  modify_ts=$(stat -c '%y' "$path")
  change_ts=$(stat -c '%z' "$path")

  echo "OK:   $name → $path"
  echo "      Modify: $modify_ts"
  echo "      Change: $change_ts"

  if (( MAX_AGE_DAYS > 0 )); then
    # find returns the path if its mtime is older than MAX_AGE_DAYS
    if find "$path" -mtime +$MAX_AGE_DAYS -print -quit | grep -q .; then
      echo "WARN: $path modified more than $MAX_AGE_DAYS days ago" >&2
      exit_code=1
    fi
  fi
done

exit $exit_code
