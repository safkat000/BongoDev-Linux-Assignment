#!/bin/bash
# Part 8: Tear everything down, in reverse build order.
# Idempotent — safe to run even if an earlier step already failed partway through.
set -uo pipefail  # no -e: we want to keep going even if a step is already gone

SVC_NAME="${SVC_NAME:-bgdsvc_safkat}"
TMPDIR="/mnt/${SVC_NAME}_tmp"

echo "==> 1. Killing anything still running as $SVC_NAME..."
sudo pkill -u "$SVC_NAME" 2>/dev/null || echo "    (nothing running)"

echo "==> 2. Removing automation (cron, logrotate, scripts)..."
sudo crontab -r -u "$SVC_NAME" 2>/dev/null || echo "    (no crontab)"
sudo rm -f "/etc/logrotate.d/$SVC_NAME"
sudo rm -f "/usr/local/bin/${SVC_NAME}_monitor.sh"
sudo rm -f "/usr/local/bin/${SVC_NAME}_cleanup_old_files.sh"

echo "==> 3. Unmounting storage..."
if mountpoint -q "$TMPDIR" 2>/dev/null; then
    sudo umount "$TMPDIR"
else
    echo "    ($TMPDIR not mounted)"
fi
sudo rmdir "$TMPDIR" 2>/dev/null || echo "    (mount point already gone)"

echo "==> 4. Removing logs..."
sudo rm -rf "/var/log/$SVC_NAME"

echo "==> 5. Removing the identity itself..."
if id "$SVC_NAME" &>/dev/null; then
    sudo userdel -r "$SVC_NAME" 2>/dev/null || sudo userdel "$SVC_NAME"
else
    echo "    (user already gone)"
fi

echo ""
echo "==> Verifying the crime scene is clean:"
echo "--- id $SVC_NAME (should fail) ---"
id "$SVC_NAME" 2>&1 || true
echo "--- mount | grep $SVC_NAME (should be empty) ---"
mount | grep "$SVC_NAME" || echo "(empty, good)"
echo "--- ps -u $SVC_NAME (should be empty) ---"
ps -u "$SVC_NAME" 2>&1 || echo "(empty, good)"