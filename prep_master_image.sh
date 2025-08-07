#!/bin/bash
#=========================================================================
# Script Name  : prepare_master_image.sh
# Description  : Prepares a RHEL 9.6 Citrix VDA master image for snapshot
# Author       : Charles Adams
# Last Updated : 2025-08-07
#=========================================================================

set -euo pipefail

#────────────────────────────────────────────────────────────
# Configuration
#────────────────────────────────────────────────────────────
TEMPLATE_PREFIX="clean-vda-template"
DATESTAMP=$(date +%Y%m%d)
TIMESTAMP=$(date +%H%M)
TAG="${DATESTAMP}_${TIMESTAMP}"
NEW_HOSTNAME="${TEMPLATE_PREFIX}-${TAG}"

#────────────────────────────────────────────────────────────
# Pre-check: Ensure 'expect' is installed
#────────────────────────────────────────────────────────────
if ! command -v expect >/dev/null 2>&1; then
    echo "🔧 'expect' not found. Installing..."
    sudo dnf install -y expect
fi

echo
echo "🔧 Citrix VDA Master Image Preparation (winbind-based)"
echo "------------------------------------------------------"
echo " New Hostname Template : $NEW_HOSTNAME"
echo

#────────────────────────────────────────────────────────────
# Step 1: Prompt for domain leave credentials and leave domain
#────────────────────────────────────────────────────────────
echo "🧩 [Step 1/7] Prompting for domain leave credentials..."

read -rp "🧑 Enter domain username [default: Administrator]: " DOMAIN_ADMIN
DOMAIN_ADMIN=${DOMAIN_ADMIN:-Administrator}

read -rsp "🔐 Enter password for $DOMAIN_ADMIN: " DOMAIN_PASS
echo

echo "🔄 Attempting to leave the domain as $DOMAIN_ADMIN..."

if net ads testjoin &>/dev/null; then
    expect <<EOF
spawn net ads leave -U "$DOMAIN_ADMIN"
expect "Password for *:"
send "$DOMAIN_PASS\r"
expect eof
EOF
    echo "✅ Successfully left the domain."
else
    echo "ℹ️ System appears to already be unjoined from the domain."
fi

#────────────────────────────────────────────────────────────
# Step 2: Stop and disable winbind (leave config intact)
#────────────────────────────────────────────────────────────
echo
echo "🛑 [Step 2/7] Stopping and disabling winbind service..."

systemctl stop winbind || echo "⚠️ winbind not running."
systemctl disable winbind || echo "⚠️ winbind not enabled."

echo "✅ winbind service stopped and disabled."

#────────────────────────────────────────────────────────────
# Step 3: Remove domain identity artifacts
#────────────────────────────────────────────────────────────
echo
echo "🧹 [Step 3/7] Cleaning domain identity artifacts (keytab, secrets)..."

rm -f /etc/krb5.keytab && echo "🗑️ Removed /etc/krb5.keytab"
rm -f /var/lib/samba/secrets.tdb && echo "🗑️ Removed /var/lib/samba/secrets.tdb"
rm -rf /var/cache/samba/* /var/lib/samba/*.tdb && echo "🗑️ Cleared Samba caches"

echo "✅ Domain-specific secrets removed. Config files preserved."

#────────────────────────────────────────────────────────────
# Step 4: Remove Citrix ad_join.service if present
#────────────────────────────────────────────────────────────
echo
echo "🚫 [Step 4/7] Removing Citrix ad_join.service if present..."

if systemctl list-unit-files | grep -q ad_join.service; then
    systemctl disable ad_join.service || true
    rm -f /etc/systemd/system/multi-user.target.wants/ad_join.service
    rm -f /var/xdl/mcs/ad_join.service
    echo "🗑️ Removed ad_join.service from systemd and MCS directory."
else
    echo "✅ ad_join.service not present or already removed."
fi

echo "🧠 NOTE: This service is only intended to run on MCS-provisioned clones."
echo "         It should never be active on the master image."

#────────────────────────────────────────────────────────────
# Step 5: Set hostname with datestamp and clear machine-id
#────────────────────────────────────────────────────────────
echo
echo "🔧 [Step 5/7] Setting hostname to '$NEW_HOSTNAME'..."

hostnamectl set-hostname "$NEW_HOSTNAME"
truncate -s 0 /etc/machine-id && echo "🗑️ Cleared /etc/machine-id"

echo "✅ Hostname updated and machine identity cleared."

#────────────────────────────────────────────────────────────
# Step 6: Clean temp and log files
#────────────────────────────────────────────────────────────
echo
echo "🧽 [Step 6/7] Cleaning temporary files and logs..."

rm -rf /var/log/* /tmp/* /var/tmp/* && echo "🧹 Logs and temp data removed."

echo "✅ System cleaned."

#────────────────────────────────────────────────────────────
# Step 7: Reminder for Manual Snapshot
#────────────────────────────────────────────────────────────
echo
echo "📦 [Step 7/7] Preparation complete!"
echo
echo "🚨 IMPORTANT: DO NOT REBOOT THIS IMAGE!"
echo "⚠️  A reboot will cause a domain mismatch and may generate new artifacts."
echo
echo "✅ Proceed to your hypervisor or cloud portal and create a snapshot of this VM."
echo
echo "💡 Suggested snapshot name:  ${NEW_HOSTNAME}-snapshot"
echo "🕒 Timestamp (UTC):           ${DATESTAMP} at ${TIMESTAMP} (HHMM)"
echo
echo "🛑 Leave this terminal open or power off the VM only after snapshot is complete."
echo
