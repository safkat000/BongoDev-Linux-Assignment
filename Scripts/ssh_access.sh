#!/bin/bash
# Part 4: Give the service account SSH key-based access (idempotent)
set -euo pipefail

SVC_NAME="${SVC_NAME:-bgdsvc_safkat}"
KEY_PATH="$HOME/.ssh/${SVC_NAME}_key"

if [ -f "$KEY_PATH" ]; then
    echo "==> Key pair already exists at $KEY_PATH. Skipping keygen."
else
    echo "==> Generating ed25519 key pair..."
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N ""
fi

echo "==> Setting up authorized_keys for $SVC_NAME..."
sudo mkdir -p "/home/$SVC_NAME/.ssh"
sudo cp "${KEY_PATH}.pub" "/home/$SVC_NAME/.ssh/authorized_keys"
sudo chown -R "$SVC_NAME:$SVC_NAME" "/home/$SVC_NAME/.ssh"
sudo chmod 700 "/home/$SVC_NAME/.ssh"
sudo chmod 600 "/home/$SVC_NAME/.ssh/authorized_keys"

echo "==> Done. Test with:"
echo "    ssh -i $KEY_PATH $SVC_NAME@localhost"
echo "    (or against your EC2 public IP once security group allows it)"