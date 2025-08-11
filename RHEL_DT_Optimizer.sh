#!/usr/bin/env bash
#------------------------------------------------------------------------------
# RHEL_DT_Optimizer.sh — RHEL 9.6 Post-Install Best Practices (Non-CIS, GNOME-safe)
# - Adds crash dump (kdump), guest tools, logrotate hygiene, weekly DNF cache cleanup,
#   sysstat metrics (60-day retention), journald persistent+cap, and user QoL.
# - EXCLUDES: chrony, systemd-resolved, XFS-specific tuning, and any CIS-affecting changes.
# - Leaves GNOME services alone.
#------------------------------------------------------------------------------
set -euo pipefail

# -----------------------------
# DryRun handling
# -----------------------------
DryRun=false
if [[ "${1:-}" =~ ^-?DryRun$ ]]; then
  DryRun=true
  echo "=== DRY RUN MODE ENABLED ==="
fi

run_cmd() {
  if $DryRun; then
    echo "[DryRun] $*"
  else
    eval "$@"
  fi
}

# -----------------------------
# [1/8] Crash dump support (kdump)
# -----------------------------
echo "=== [1/8] Crash dump support (kdump) ==="
run_cmd "sudo dnf install -y kexec-tools"
run_cmd "sudo systemctl enable --now kdump"

# -----------------------------
# [2/8] Virtualization guest tools (auto-detect)
# -----------------------------
echo "=== [2/8] Virtualization guest tools (auto-detect) ==="
virt="$(systemd-detect-virt || true)"
if [[ "$virt" == "kvm" ]]; then
  run_cmd "sudo dnf install -y qemu-guest-agent"
  run_cmd "sudo systemctl enable --now qemu-guest-agent"
elif [[ "$virt" == "vmware" ]]; then
  run_cmd "sudo dnf install -y open-vm-tools"
  run_cmd "sudo systemctl enable --now vmtoolsd"
else
  echo "No recognized hypervisor detected (virt='${virt}'); skipping guest agent install."
fi

# -----------------------------
# [3/8] Journald: persistent & capped (prevent runaways)
# -----------------------------
echo "=== [3/8] Journald persistent + caps ==="
run_cmd "sudo mkdir -p /var/log/journal"
run_cmd "sudo chmod 2755 /var/log/journal"
run_cmd "sudo chown root:systemd-journal /var/log/journal"
run_cmd "sudo mkdir -p /etc/systemd/journald.conf.d"
run_cmd "sudo tee /etc/systemd/journald.conf.d/99-persistent-cap.conf >/dev/null <<'EOF'
[Journal]
Storage=persistent
# Total journal usage cap (generous but bounded)
SystemMaxUse=200M
# Per-file cap
SystemMaxFileSize=50M
# Upper bound on number of rotated files (SystemMaxUse takes precedence)
SystemMaxFiles=8
EOF"
run_cmd "sudo systemctl restart systemd-journald"

# -----------------------------
# [4/8] Log rotation sanity (weekly, 12 rotations, compressed)
# - Back up existing /etc/logrotate.conf, then write sane defaults.
# -----------------------------
echo "=== [4/8] Logrotate defaults (weekly, rotate=12, compress) ==="
if [[ -f /etc/logrotate.conf ]]; then
  ts="$(date +%F_%H%M%S)"
  run_cmd "sudo cp /etc/logrotate.conf /etc/logrotate.conf.bak.${ts}"
fi
run_cmd "sudo dnf install -y logrotate"
run_cmd "sudo tee /etc/logrotate.conf >/dev/null <<'EOF'
# Global logrotate defaults
weekly
rotate 12
compress
delaycompress
notifempty
create

# Include service-specific rules
include /etc/logrotate.d
EOF"
# Dry-run validation (won't modify anything)
run_cmd "sudo logrotate -d /etc/logrotate.conf || true"

# -----------------------------
# [5/8] Service footprint (GNOME-safe)
# - Disable server-side cruft only; do not touch GNOME/desktop daemons.
# -----------------------------
echo "=== [5/8] Disable unused services (cups, bluetooth, postfix, rpcbind) ==="
for svc in cups bluetooth postfix rpcbind; do
  run_cmd "sudo systemctl disable --now ${svc}.service 2>/dev/null || true"
  run_cmd "sudo systemctl disable --now ${svc}.socket 2>/dev/null || true"
done

# -----------------------------
# [6/8] Weekly DNF cache cleanup timer
# -----------------------------
echo "=== [6/8] Weekly DNF cache cleanup timer ==="
run_cmd "sudo tee /etc/systemd/system/dnf-cache-clean.timer >/dev/null <<'EOF'
[Unit]
Description=Weekly DNF cache cleanup timer
[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF"
run_cmd "sudo tee /etc/systemd/system/dnf-cache-clean.service >/dev/null <<'EOF'
[Unit]
Description=DNF cache cleanup
[Service]
Type=oneshot
ExecStart=/usr/bin/dnf clean all -y
EOF"
run_cmd "sudo systemctl daemon-reload"
run_cmd "sudo systemctl enable --now dnf-cache-clean.timer"

# -----------------------------
# [7/8] Sysstat metrics (enable + 60-day retention)
# -----------------------------
echo "=== [7/8] Sysstat metrics (60-day retention) ==="
run_cmd "sudo dnf install -y sysstat"
# Ensure ENABLED=true
run_cmd "sudo sed -i 's/^ENABLED=\"false\"/ENABLED=\"true\"/' /etc/sysconfig/sysstat || true"
# Ensure HISTORY=60 (append if missing)
run_cmd "grep -q '^HISTORY=' /etc/sysconfig/sysstat && sudo sed -i 's/^HISTORY=.*/HISTORY=60/' /etc/sysconfig/sysstat || echo 'HISTORY=60' | sudo tee -a /etc/sysconfig/sysstat >/dev/null"
run_cmd "sudo systemctl enable --now sysstat"

# -----------------------------
# [8/8] User environment QoL (nofile + history)
# -----------------------------
echo "=== [8/8] User QoL (nofile=65535, large deduped history) ==="
run_cmd "sudo tee /etc/security/limits.d/90-nofiles.conf >/dev/null <<'EOF'
* soft nofile 65535
* hard nofile 65535
EOF"
run_cmd "sudo tee /etc/profile.d/history.sh >/dev/null <<'EOF'
export HISTCONTROL=ignoredups:erasedups
export HISTSIZE=100000
export HISTFILESIZE=200000
shopt -s histappend
EOF"

echo "=== BASELINE COMPLETE ==="
echo "Reboot recommended if kdump was newly enabled."
