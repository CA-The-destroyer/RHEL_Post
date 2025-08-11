#!/usr/bin/env bash
#------------------------------------------------------------------------------
# rhel96-baseline.sh — RHEL 9.6 Post-Install Best Practices (No CIS, GNOME-safe)
#------------------------------------------------------------------------------
set -euo pipefail

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

echo "=== [1/7] Crash dump support (kdump) ==="
run_cmd "sudo dnf install -y kexec-tools"
run_cmd "sudo systemctl enable --now kdump"

echo "=== [2/7] Virtualization guest tools ==="
# Detect virt and install matching guest agent (safe for GNOME)
virt=$(systemd-detect-virt || true)
if [[ "$virt" == "kvm" ]]; then
    run_cmd "sudo dnf install -y qemu-guest-agent"
    run_cmd "sudo systemctl enable --now qemu-guest-agent"
elif [[ "$virt" == "vmware" ]]; then
    run_cmd "sudo dnf install -y open-vm-tools"
    run_cmd "sudo systemctl enable --now vmtoolsd"
fi

echo "=== [3/7] Log rotation sanity ==="
run_cmd "sudo dnf install -y logrotate"
run_cmd "sudo logrotate -d /etc/logrotate.conf || true"

echo "=== [4/7] Service footprint review (safe set) ==="
# Leave GNOME-related daemons intact; disable only harmless server cruft
for svc in cups bluetooth postfix rpcbind; do
    run_cmd "sudo systemctl disable --now ${svc}.service 2>/dev/null || true"
    run_cmd "sudo systemctl disable --now ${svc}.socket 2>/dev/null || true"
done

echo "=== [5/7] Weekly DNF cache cleanup timer ==="
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
run_cmd "sudo systemctl enable --now dnf-cache-clean.timer"

echo "=== [6/7] Sysstat historic metrics ==="
run_cmd "sudo dnf install -y sysstat"
run_cmd "sudo sed -i 's/^ENABLED=\"false\"/ENABLED=\"true\"/' /etc/sysconfig/sysstat"
run_cmd "sudo systemctl enable --now sysstat"

echo "=== [7/7] User environment quality-of-life ==="
# No CIS impact, just shell usability
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
echo "Reboot if kdump was newly enabled."
