#!/bin/bash
# Part 5: Harden SSH — change port, disable root login & password auth,
# restrict to the service account only.
#
# !!! EC2 WARNING !!!
# Before running this, open port 2222 in your EC2 Security Group and
# confirm you can reach it. If you restart sshd before that, you can
# lock yourself out of the instance.
set -euo pipefail

SVC_NAME="${SVC_NAME:-bgdsvc_safkat}"
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.bak.$(date +%s)"
NEW_PORT=2222

echo "==> Backing up $SSHD_CONFIG to $BACKUP"
sudo cp "$SSHD_CONFIG" "$BACKUP"

apply_setting() {
    local key="$1" value="$2"
    if sudo grep -qE "^\s*#?\s*${key}\b" "$SSHD_CONFIG"; then
        sudo sed -i -E "s|^\s*#?\s*${key}\b.*|${key} ${value}|" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    fi
}

echo "==> Applying hardening settings for $SVC_NAME on port $NEW_PORT..."
apply_setting "Port" "$NEW_PORT"
apply_setting "PermitRootLogin" "no"
apply_setting "PasswordAuthentication" "no"
apply_setting "AllowUsers" "$SVC_NAME"

echo "==> Validating sshd config syntax..."
sudo sshd -t

echo "==> Config looks valid. Restarting ssh..."

# On recent Ubuntu, ssh.socket controls the actual listening port via
# systemd socket activation, independent of sshd_config. If it's active,
# it will keep listening on the old port even after sshd_config is changed
# and ssh.service is restarted. Disable it so sshd binds directly to the
# port defined in sshd_config instead.
if systemctl is-active --quiet ssh.socket 2>/dev/null; then
    echo "==> ssh.socket is active; disabling it so sshd binds to sshd_config's Port directly..."
    sudo systemctl disable --now ssh.socket
fi

sudo systemctl restart ssh.service 2>/dev/null || sudo systemctl restart sshd

echo "==> Verifying sshd is actually listening on port $NEW_PORT..."
sudo ss -tlnp | grep ":$NEW_PORT" || echo "WARNING: nothing appears to be listening on $NEW_PORT yet — check 'sudo ss -tlnp | grep ssh'"

echo "==> Done. From here on, only $SVC_NAME can log in, and only on port $NEW_PORT."
echo "    Test in a NEW terminal (keep this session open) with:"
echo "    ssh -i ~/.ssh/${SVC_NAME}_key -p $NEW_PORT $SVC_NAME@<ec2-public-ip>"