#!/bin/bash
# Part 3: Stress test the service — disk, CPU, memory, or all at once
# Usage: ./03_stress_and_populate.sh --cpu | --mem | --disk | --all
set -euo pipefail

SVC_NAME="${SVC_NAME:-bgdsvc_safkat}"
TMPDIR="/mnt/${SVC_NAME}_tmp"

usage() {
    echo "Usage: $0 --cpu | --mem | --disk | --all"
    exit 1
}

[ $# -eq 1 ] || usage

if ! mountpoint -q "$TMPDIR" 2>/dev/null; then
    echo "ERROR: $TMPDIR is not mounted. Run 02_setup_tmpfs.sh first."
    exit 1
fi

fill_disk() {
    echo "==> 3.1 Filling disk (tmpfs cap is 256M)..."
    for i in $(seq 1 20); do
        dd if=/dev/urandom of="$TMPDIR/file_$i.dat" bs=1M count=10 2>&1 | tail -n 1 || true
        df -h "$TMPDIR"
    done
}

push_cpu() {
    echo "==> 3.2 Pushing CPU for 30s..."
    if command -v stress-ng &>/dev/null; then
        sudo -u "$SVC_NAME" stress-ng --cpu 2 --timeout 30s --temp-path "$TMPDIR"
    else
        echo "stress-ng not found, improvising with yes..."
        yes > /dev/null &
        yes > /dev/null &
        PIDS="$! $!"
        sleep 30
        kill $PIDS 2>/dev/null || true
    fi
}

squeeze_memory() {
    echo "==> 3.3 Squeezing memory for 30s..."
    sudo -u "$SVC_NAME" stress-ng --vm 1 --vm-bytes 200M --timeout 30s --temp-path "$TMPDIR"
}

run_all() {
    echo "==> 3.4 Running CPU + memory + disk fill together..."
    fill_disk &
    DISK_PID=$!
    sudo -u "$SVC_NAME" stress-ng --cpu 2 --vm 1 --vm-bytes 200M --timeout 30s --temp-path "$TMPDIR" &
    STRESS_PID=$!
    echo "==> Watch in a second terminal: free -h / top / dmesg | grep -i oom"
    wait $DISK_PID $STRESS_PID 2>/dev/null || true
    echo "==> Combined stress run finished. Checking for OOM events:"
    sudo dmesg | grep -i oom || echo "(no OOM events found)"
}

case "$1" in
    --disk) fill_disk ;;
    --cpu)  push_cpu ;;
    --mem)  squeeze_memory ;;
    --all)  run_all ;;
    *) usage ;;
esac