#!/bin/bash
set -euo pipefail

LOG_FILE="/opt/dev-env/logs/actions.log"
USERNAME="$1"

# ===== BASIC VALIDATION =====
if [[ -z "$USERNAME" ]]; then
  echo "Usage: create-user.sh <username>"
  exit 1
fi

# Block root explicitly
if [[ "$USERNAME" == "root" ]]; then
  echo "Cannot create root user"
  exit 1
fi

# Username format
if [[ ! "$USERNAME" =~ ^[a-z0-9_]{3,16}$ ]]; then
  echo "Invalid username. Use 3–16 chars: a-z, 0-9, _"
  exit 1
fi

# ===== CHECK EXISTENCE =====
if id "$USERNAME" &>/dev/null; then
  echo "User already exists"
  exit 1
fi

# ===== CREATE USER (NO LOGIN, NO SHELL) =====
useradd -m -s /usr/sbin/nologin "$USERNAME"

# ===== SECURE HOME DIRECTORY =====
chmod 700 "/home/$USERNAME"

# ===== BLOCK PASSWORD LOGIN =====
passwd -l "$USERNAME"

# ===== BLOCK SSH (AUTHORIZED KEYS) =====
SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
chown root:root "$SSH_DIR"
chmod 000 "$SSH_DIR"

# ===== REMOVE SHELL PROFILE FILES =====
rm -f \
  "/home/$USERNAME/.bashrc" \
  "/home/$USERNAME/.profile" \
  "/home/$USERNAME/.bash_logout"

# ===== PREVENT CRON / AT USAGE (PER USER) =====
echo "$USERNAME" >> /etc/cron.deny
echo "$USERNAME" >> /etc/at.deny

# ===== LIMIT USER RESOURCES (PER USER) =====
LIMITS_FILE="/etc/security/limits.d/dev-env-$USERNAME.conf"
cat <<EOF > "$LIMITS_FILE"
$USERNAME hard nproc 100
$USERNAME hard nofile 1024
$USERNAME hard fsize 1048576
EOF

chmod 644 "$LIMITS_FILE"

# ===== FORCE SAFE UMASK FOR THIS USER =====
echo "UMASK 077" >> /etc/login.defs

# ===== LOG ACTION =====
echo "$(date '+%Y-%m-%d %H:%M:%S') | CREATE_USER | $USERNAME" >> "$LOG_FILE"

echo "User $USERNAME created and fully restricted (code-server only)"
