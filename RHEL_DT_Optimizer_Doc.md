# RHEL 9.6 Desktop-Safe Optimizer (Non-CIS) — Handoff

**Script Name:** `RHEL_DT_Optimizer.sh`  
**Purpose:** Post-install baseline for RHEL 9.6 that’s **safe for GNOME desktop environments** and **avoids CIS control overlap**.

[📥 Download `RHEL_DT_Optimizer.sh`](./RHEL_DT_Optimizer.sh)

---

## What this script does

- Brings a RHEL 9.6 desktop or workstation to a stable, performant baseline.
- Improves **reliability** (kdump, guest tools), **operability** (logrotate, timers), and **observability** (sysstat) without breaking GNOME services.
- Adds user environment quality-of-life settings.
- **Does not** modify CIS-controlled settings, network time sync, systemd-resolved, or XFS-specific options.

---

## How to run

```bash
chmod +x RHEL_DT_Optimizer.sh

# Preview changes only (no changes made)
./RHEL_DT_Optimizer.sh -DryRun

# Apply changes
./RHEL_DT_Optimizer.sh
```

---

## Actions in detail

### 1) Crash dump support (kdump)
- **Installs:** `kexec-tools`
- **Enables:** `kdump.service`
- **Why:** Captures vmcore on kernel panic for debugging.
- **Verify:**  
  ```bash
  systemctl status kdump
  ```

---

### 2) Virtualization guest tools (auto-detect)
- **KVM:** Installs and enables `qemu-guest-agent`
- **VMware:** Installs and enables `open-vm-tools`
- **Why:** Hypervisor integration (shutdown, IP reporting, time sync).
- **Verify:**  
  ```bash
  systemd-detect-virt
  systemctl status qemu-guest-agent || systemctl status vmtoolsd
  ```

---

### 3) Log rotation sanity
- **Installs:** `logrotate`
- **Tests config:** `logrotate -d /etc/logrotate.conf`
- **Why:** Prevents log files from consuming all disk space.
- **Verify:**  
  ```bash
  logrotate -d /etc/logrotate.conf
  ```

---

### 4) Service footprint review (GNOME-safe)
- Disables **only**: `cups`, `bluetooth`, `postfix`, `rpcbind`
- Leaves GNOME and desktop services intact.
- **Why:** Removes unused background daemons to reduce boot time/memory.
- **Verify:**  
  ```bash
  systemctl is-enabled cups bluetooth postfix rpcbind
  ```

---

### 5) Weekly DNF cache cleanup
- Creates `/etc/systemd/system/dnf-cache-clean.timer` and `.service`
- Runs `dnf clean all -y` weekly at 03:00 on Sundays.
- **Why:** Reduces disk use and stale metadata.
- **Verify:**  
  ```bash
  systemctl list-timers | grep dnf-cache-clean
  ```

---

### 6) Sysstat metrics
- **Installs:** `sysstat`
- **Enables:** `sysstat.service` with `ENABLED="true"` in `/etc/sysconfig/sysstat`
- **Why:** Historic CPU/disk/memory performance data for troubleshooting.
- **Verify:**  
  ```bash
  sar -u 1 3
  ```

---

### 7) User QoL settings
- **nofile limits:** `/etc/security/limits.d/90-nofiles.conf` (65535 soft/hard)
- **Bash history:** `/etc/profile.d/history.sh` for large, deduped history.
- **Why:** Avoids “too many open files” issues; makes shell history more useful.
- **Verify:**  
  ```bash
  ulimit -n
  echo $HISTSIZE $HISTFILESIZE $HISTCONTROL
  ```

---

## Safety
- Idempotent: Safe to re-run anytime.
- DryRun mode to preview.
- No interference with CIS, GNOME, or core desktop services.

---

## Post-run checks
```bash
systemctl status kdump
systemd-detect-virt
systemctl list-timers | grep dnf-cache-clean
systemctl status sysstat
ulimit -n
```
