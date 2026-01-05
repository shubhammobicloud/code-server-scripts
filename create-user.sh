#!/bin/bash
set -euo pipefail

LOG_DIR="/opt/dev-env/logs"
LOG_FILE="$LOG_DIR/actions.log"

# ================================
# CREATE LOG DIRECTORY IF MISSING
# ================================
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"

# ================================
# GET USERNAME
# ================================
USERNAME="${1:-}"

if [[ -z "$USERNAME" ]]; then
  read -p "Enter username to create: " USERNAME
fi

# ================================
# BASIC VALIDATION
# ================================
if [[ "$USERNAME" == "root" ]]; then
  echo "❌ Cannot create root user"
  exit 1
fi

if [[ ! "$USERNAME" =~ ^[a-z0-9_]{3,16}$ ]]; then
  echo "❌ Invalid username. Use 3–16 chars: a-z, 0-9, _"
  exit 1
fi

# ================================
# REMOVE OLD USER IF NEEDED
# ================================
if id "$USERNAME" &>/dev/null; then
  read -p "User $USERNAME exists. Delete and recreate? (y/N): " CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    systemctl stop "code-server@$USERNAME" 2>/dev/null || true
    systemctl disable "code-server@$USERNAME" 2>/dev/null || true
    pkill -9 -u "$USERNAME" 2>/dev/null || true
    userdel -r "$USERNAME"
    echo "Old user $USERNAME removed."
  else
    echo "Exiting without changes."
    exit 0
  fi
fi

# ================================
# CREATE RESTRICTED USER
# ================================
useradd -m -s /usr/sbin/nologin "$USERNAME"
chmod 700 "/home/$USERNAME"
passwd -l "$USERNAME"  # lock password login

# ================================
# SECURE SSH DIR
# ================================
SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
chown root:root "$SSH_DIR"
chmod 000 "$SSH_DIR"

# ================================
# REMOVE AND LOCK PROFILE FILES
# ================================
for file in .bashrc .profile .bash_logout; do
    FILE_PATH="/home/$USERNAME/$file"
    rm -f "$FILE_PATH"
    touch "$FILE_PATH"
    chown root:root "$FILE_PATH"
    chmod 444 "$FILE_PATH"  # read-only
done

# ================================
# DENY CRON / AT
# ================================
grep -qxF "$USERNAME" /etc/cron.deny || echo "$USERNAME" >> /etc/cron.deny
grep -qxF "$USERNAME" /etc/at.deny   || echo "$USERNAME" >> /etc/at.deny

# ================================
# RESOURCE LIMITS
# ================================
LIMITS_FILE="/etc/security/limits.d/dev-env-$USERNAME.conf"
cat <<EOF > "$LIMITS_FILE"
$USERNAME hard nproc 100
$USERNAME hard nofile 1024
$USERNAME hard fsize 1048576
EOF
chmod 644 "$LIMITS_FILE"

# ================================
# SAFE UMASK
# ================================
UMASK_LINE="UMASK 077"
if ! grep -q "^$UMASK_LINE" /etc/login.defs; then
  echo "$UMASK_LINE" >> /etc/login.defs
fi

# ================================
# LOG ACTION
# ================================
echo "$(date '+%Y-%m-%d %H:%M:%S') | CREATE_USER | $USERNAME" >> "$LOG_FILE"

echo "✅ User '$USERNAME' created and fully restricted."
echo "🔒 .ssh and profile files are read-only for user"
echo "👤 Home directory chmod 700"
