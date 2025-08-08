#!/bin/bash
# Toggle ONLY the Citrix MCS AD-join flag (ad_join.service)
# Usage:
#   mcs-flag.sh status   # show current state
#   mcs-flag.sh on       # enable (for clones; NOT for master)
#   mcs-flag.sh off      # disable (recommended for master)

set -euo pipefail

UNIT_NAME="ad_join.service"
UNIT_PATH="/var/xdl/mcs/${UNIT_NAME}"
WANTS_LINK="/etc/systemd/system/multi-user.target.wants/${UNIT_NAME}"

cmd="${1:-status}"

status() {
  echo "Unit file:   $([[ -f $UNIT_PATH ]] && echo 'present' || echo 'missing')  ($UNIT_PATH)"
  if systemctl list-unit-files | grep -q "^${UNIT_NAME}\s"; then
    state=$(systemctl is-enabled "${UNIT_NAME}" || true)
    echo "Systemd reg: ${state}"
  else
    echo "Systemd reg: not-registered"
  fi
  echo "Wants link:  $([[ -L $WANTS_LINK ]] && echo 'present' || echo 'absent')  ($WANTS_LINK)"
}

enable_flag() {
  # You should only enable this on *clones* or if you're explicitly testing join-on-boot.
  if [[ ! -f "$UNIT_PATH" ]]; then
    echo "Unit file missing at $UNIT_PATH."
    echo "→ Re-run /opt/Citrix/VDA/sbin/deploymcs.sh to regenerate it, then rerun this with 'on'."
    exit 1
  fi

  # Register unit if needed; then enable via symlink
  systemctl daemon-reload
  systemctl enable "$UNIT_PATH" 2>/dev/null || true
  ln -sf "$UNIT_PATH" "$WANTS_LINK"
  systemctl daemon-reload
  echo "ad_join.service flag ENABLED (link created)."
}

disable_flag() {
  # Remove only the enablement; keep the unit file so deploymcs.sh stays happy.
  systemctl disable "${UNIT_NAME}" 2>/dev/null || true
  rm -f "$WANTS_LINK"
  systemctl daemon-reload
  echo "ad_join.service flag DISABLED (link removed)."
}

case "$cmd" in
  status)  status ;;
  on)      enable_flag ;;
  off)     disable_flag ;;
  *) echo "Usage: $0 {status|on|off}"; exit 2 ;;
esac
