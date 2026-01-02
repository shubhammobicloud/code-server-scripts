#!/bin/bash
set -euo pipefail

LOG_FILE="/opt/dev-env/logs/actions.log"
USERNAME="$1"

# ===== BASIC VALIDATION =====
if [[ -z "$USERNAME" ]]; then
  echo "Usage: create-user.sh <username>"
  exit 1
fi

# Block root and system users
if [[ "$USERNAME" == "root" ]]; then
  echo "Cannot create root user"
  exit 1
fi

if [[ ! "$USERNAME" =~ ^[a-z0-9_]{3,16}$ ]]; then
  echo "Invalid username. Use 3–16 chars: a-z, 0-9, _"
  exit 1
fi

# ===== CHECK EXISTENCE =====
if id "$USERNAME" &>/dev/null; then
  echo "User already exists"
  exit 1
fi

# ===== CREATE USER (NO LOGIN SHELL) =====
useradd \
  -m \
  -s /usr/sbin/nologin \
  "$USERNAME"

# ===== SECURE HOME =====
chmod 700 "/home/$USERNAME"

# ===== BLOCK PASSWORD LOGIN =====
passwd -l "$USERNAME"

# ===== BLOCK SSH KEYS =====
SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
chmod 000 "$SSH_DIR"
chown root:root "$SSH_DIR"

# ===== REMOVE PROFILE FILES =====
rm -f \
  "/home/$USERNAME/.bashrc" \
  "/home/$USERNAME/.profile" \
  "/home/$USERNAME/.bash_logout"

# ===== PREVENT RECREATION OF SHELL FILES =====
touch /etc/skel/.bashrc
chmod 644 /etc/skel/.bashrc

# ===== LOG =====
echo "$(date '+%Y-%m-%d %H:%M:%S') | CREATE_USER | $USERNAME" >> "$LOG_FILE"

echo "User $USERNAME created with login fully blocked"
