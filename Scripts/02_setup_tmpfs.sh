#!/bin/bash
# Part 2: Set up tmpfs scratch space, capped at 256M (idempotent)
set -euo pipefail

SVC_NAME="${SVC_NAME:-bgdsvc_safkat}"
TMPDIR="/mnt/${SVC_NAME}_tmp"

echo "==> Creating mount point $TMPDIR (if needed)..."
sudo mkdir -p "$TMPDIR"

if mountpoint -q "$TMPDIR"; then
    echo "==> $TMPDIR is already mounted as tmpfs. Skipping mount."
else
    echo "==> Mounting tmpfs at $TMPDIR with size cap 256M..."
    sudo mount -t tmpfs -o size=256M tmpfs "$TMPDIR"
fi

echo "==> Setting ownership to $SVC_NAME..."
sudo chown "$SVC_NAME:$SVC_NAME" "$TMPDIR"

echo "==> Verification:"
df -h "$TMPDIR"