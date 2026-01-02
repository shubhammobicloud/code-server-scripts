#!/bin/bash
set -euo pipefail

LOG_DIR="/opt/dev-env/logs"
LOG_FILE="$LOG_DIR/actions.log"

# ===== CREATE LOG DIRECTORY IF MISSING =====
if [[ ! -d "$LOG_DIR" ]]; then
  mkdir -p "$LOG_DIR"
  chmod 755 "$LOG_DIR"
fi

# ===== GET USERNAME =====
USERNAME="${1:-}"

# Prompt if not passed as argument
if [[ -z "$USERNAME" ]]; then
  read -p "Enter username to create: " USERNAME
fi

# ===== BASIC VALIDATION =====
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
  read -p "User $USERNAME already exists. Do you want to delete and recreate? (y/N): " CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    # Stop any services for this user first
    systemctl stop "code-server@$USERNAME" 2>/dev/null || true
    systemctl disable "code-server@$USERNAME" 2>/dev/null || true
    pkill -9 -u "$USERNAME" 2>/dev/null || true
    userdel -r "$USERNAME"
    echo "Old user $USERNAME removed."
  else
    echo "Exiting without creating user."
    exit 0
  fi
fi

# ===== CREATE USER (NO LOGIN SHELL) =====
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
rm -f "/home/$USERNAME/.bashrc" \
      "/home/$USERNAME/.profile" \
      "/home/$USERNAME/.bash_logout"

# ===== PREVENT CRON / AT USAGE =====
echo "$USERNAME" >> /etc/cron.deny
echo "$USERNAME" >> /etc/at.deny

# ===== LIMIT USER RESOURCES =====
LIMITS_FILE="/etc/security/limits.d/dev-env-$USERNAME.conf"
cat <<EOF > "$LIMITS_FILE"
$USERNAME hard nproc 100
$USERNAME hard nofile 1024
$USERNAME hard fsize 1048576
EOF
chmod 644 "$LIMITS_FILE"

# ===== FORCE SAFE UMASK =====
UMASK_LINE="UMASK 077"
if ! grep -q "^$UMASK_LINE" /etc/login.defs; then
  echo "$UMASK_LINE" >> /etc/login.defs
fi

# ===== LOG ACTION =====
echo "$(date '+%Y-%m-%d %H:%M:%S') | CREATE_USER | $USERNAME" >> "$LOG_FILE"

echo "User $USERNAME created and fully restricted (code-server only)"
