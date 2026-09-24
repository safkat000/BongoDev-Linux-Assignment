#!/bin/bash
# Part 6: Nightly cleanup of stale scratch files, run at 2 AM via cron.
# NOTE: SVC_NAME is hardcoded literally here — cron does not inherit
# your interactive shell's exported variables.
SVC_NAME="bgdsvc_safkat"
TMPDIR="/mnt/${SVC_NAME}_tmp"
LOGFILE="/var/log/${SVC_NAME}/monitor.log"

# Remove test files older than 1 day so scratch space doesn't fill with stale runs
find "$TMPDIR" -type f -mtime +1 -delete
echo "$(date): cleanup run — removed files older than 1 day from $TMPDIR" >> "$LOGFILE"