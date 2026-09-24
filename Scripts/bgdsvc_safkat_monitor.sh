#!/bin/bash
# Part 6: Self-monitoring script, run every 5 minutes via cron.
# NOTE: SVC_NAME is hardcoded literally here — cron does not inherit
# your interactive shell's exported variables.
SVC_NAME="bgdsvc_safkat"
LOGFILE="/var/log/${SVC_NAME}/monitor.log"

echo "---- $(date) ----" >> "$LOGFILE"
free -h >> "$LOGFILE"
df -h "/mnt/${SVC_NAME}_tmp" >> "$LOGFILE" 2>&1
ps -u "$SVC_NAME" >> "$LOGFILE" 2>&1