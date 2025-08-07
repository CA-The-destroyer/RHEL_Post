#!/bin/bash
#=========================================================================
# Script Name  : prepare_master_image.sh
# Description  : Prepares a RHEL 9.6 Citrix VDA master image for snapshot
# Last Updated : 2025-08-07
#=========================================================================

set -euo pipefail

#────────────────────────────────────────────────────────────
# Configuration
#────────────────────────────────────────────────────────────

DOMAIN_ADMIN="Administrator"
TEMPLATE_PREFIX="clean-vda-template"

# Long-form date and short-form time (e.g., 20250807_1345)
DATESTAMP=$(date +%Y%m%d)
TIMESTAMP=$(date +%H%M)
TAG="${DATESTAMP}_${TIMESTAMP}"

NEW_HOSTNAME="${TEMPLATE_PREFIX}-${TAG}"

echo
echo "🔧 Citrix VDA Master Image Preparation (winbind-based)"
echo "------------------------------------------------------"
echo " Domain Admin User     : $DOMAIN_ADMIN"
echo " New Hostname Template : $NEW_HOSTNAME"
echo

#────────────────────────────────────────────────────────────
# Step 1: Leave the Domain (if still joined)
#────────────────────────────────────────────────────────────
echo "🧩 [Step 1/6] Attempting to leave the domain gracefully..."

if net ads testjoin &>/dev/null; then
    net ads leave -U "$DOMAIN_ADMIN" || {
        echo "❌ ERROR: Failed to leave the domain. You may already be unjoined."
        exit 1
    }
    echo "✅ Successfully left the domain."
else
    echo "ℹ️ System appears to already be unjoined from the domain."
fi

#────────────────────────────────────────────────────────────
# Step 2: Stop and disable winbind (leave config intact)
#────────────────────────────────────────────────────────────
echo
echo "🛑 [Step 2/6] Stopping and disabling winbind service..."

systemctl stop winbind || echo "⚠️ winbind not running."
systemctl disable winbind || echo "⚠️ winbind not enabled."

echo "✅ winbind service stopped and disabled."

#────────────────────────────────────────────────────────────
# Step 3: Remove domain identity artifacts
#────────────────────────────────────────────────────────────
echo
echo "🧹 [Step 3/6] Cleaning domain identity artifacts (keytab, secrets)..."

rm -f /etc/krb5.keytab && echo "🗑️ Removed /etc/krb5.keytab"
rm -f /var/lib/samba/secrets.tdb && echo "🗑️ Removed /var/lib/samba/secrets.tdb"
rm -rf /var/cache/samba/* /var/lib/samba/*.tdb && echo "🗑️ Cleared Samba caches"

echo "✅ Domain-specific secrets removed. Config files preserved."

#────────────────────────────────────────────────────────────
# Step 4: Set hostname with datestamp + time
#────────────────────────────────────────────────────────────
echo
echo "🔧 [Step 4/6] Setting hostname to '$NEW_HOSTNAME'..."

hostnamectl set-hostname "$NEW_HOSTNAME"
truncate -s 0 /etc/machine-id && echo "🗑️ Cleared /etc/machine-id"

echo "✅ Hostname updated and machine identity cleared."

#────────────────────────────────────────────────────────────
# Step 5: Clean temp and log files
#────────────────────────────────────────────────────────────
echo
echo "🧽 [Step 5/6] Cleaning temporary files and logs..."

rm -rf /var/log/* /tmp/* /var/tmp/* && echo "🧹 Logs and temp data removed."

echo "✅ System cleaned."

#────────────────────────────────────────────────────────────
# Step 6: Reminder for Manual Snapshot
#────────────────────────────────────────────────────────────
echo
echo "📦 [Step 6/6] Preparation complete!"
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
