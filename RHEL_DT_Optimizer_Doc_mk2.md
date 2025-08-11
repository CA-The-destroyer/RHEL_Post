# RHEL 9.6 Desktop-Safe Optimizer (Non-CIS) — Handoff

**Script Name:** `RHEL_DT_Optimizer.sh`  
**Purpose:** Post-install baseline for RHEL 9.6 that’s **safe for GNOME desktop environments** and **avoids CIS control overlap**.

[📥 Download `RHEL_DT_Optimizer.sh`](./RHEL_DT_Optimizer.sh)

---

## What this script does

- Brings a RHEL 9.6 desktop or workstation to a stable, performant baseline.
- Improves **reliability** (kdump, guest tools), **operability** (logrotate, timers), and **observability** (sysstat) without breaking GNOME services.
- Adds user environment quality-of-life settings.
- Adds **log size caps** for journald, logrotate, and sysstat to prevent disk runaways.
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

### 3) Journald persistent logs with caps
- **Creates:** `/var/log/journal` for persistence
- **Sets caps:**  
  - Total usage: **200 MB**
  - Per-file: **50 MB**
  - Max rotated files: **8**
- **Why:** Prevents journald logs from growing indefinitely while keeping generous history.
- **Verify:**  
  ```bash
  journalctl --disk-usage
  cat /etc/systemd/journald.conf.d/99-persistent-cap.conf
  ```

---

### 4) Log rotation sanity (weekly, 12 rotations, compressed)
- **Backs up** `/etc/logrotate.conf` if present
- **Installs:** `logrotate`
- **Configures:**  
  - Rotate weekly  
  - Keep 12 rotations (~3 months)  
  - Compress old logs  
  - Avoid empty logs (`notifempty`)
- **Why:** Prevents application logs from consuming all disk space.
- **Verify:**  
  ```bash
  logrotate -d /etc/logrotate.conf
  ```

---

### 5) Service footprint review (GNOME-safe)
- Disables **only**: `cups`, `bluetooth`, `postfix`, `rpcbind`
- Leaves GNOME and desktop services intact.
- **Why:** Removes unused background daemons to reduce boot time/memory.
- **Verify:**  
  ```bash
  systemctl is-enabled cups bluetooth postfix rpcbind
  ```

---

### 6) Weekly DNF cache cleanup
- Creates `/etc/systemd/system/dnf-cache-clean.timer` and `.service`
- Runs `dnf clean all -y` weekly at 03:00 on Sundays.
- **Why:** Reduces disk use and stale metadata.
- **Verify:**  
  ```bash
  systemctl list-timers | grep dnf-cache-clean
  ```

---

### 7) Sysstat metrics with 60-day retention
- **Installs:** `sysstat`
- **Configures:**  
  - `ENABLED="true"` in `/etc/sysconfig/sysstat`  
  - `HISTORY=60` for 60-day metric retention
- **Why:** Historic CPU/disk/memory performance data for troubleshooting without excessive storage use.
- **Verify:**  
  ```bash
  sar -u 1 3
  grep HISTORY /etc/sysconfig/sysstat
  ```

---

### 8) User QoL settings
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
- Log growth is now bounded for journald, logrotate, and sysstat.

---

## Post-run checks
```bash
systemctl status kdump
systemd-detect-virt
systemctl list-timers | grep dnf-cache-clean
systemctl status sysstat
journalctl --disk-usage
ulimit -n
```
