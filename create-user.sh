#!/bin/bash
set -euo pipefail

LOG_DIR="/opt/dev-env/logs"
LOG_FILE="$LOG_DIR/actions.log"

mkdir -p "$LOG_DIR"
chown root:root "$LOG_DIR"
chmod 755 "$LOG_DIR"

USERNAME="${1:-}"
if [[ -z "$USERNAME" ]]; then
  read -p "Enter username to create: " USERNAME
fi

# ================================
# VALIDATION
# ================================
if [[ "$USERNAME" == "root" ]]; then
  echo "❌ Cannot use root"
  exit 1
fi

if [[ ! "$USERNAME" =~ ^[a-z0-9_]{3,16}$ ]]; then
  echo "❌ Invalid username"
  exit 1
fi

# ================================
# REMOVE EXISTING USER
# ================================
if id "$USERNAME" &>/dev/null; then
  read -p "User exists. Delete and recreate? (y/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 0

  systemctl stop "code-server@$USERNAME" 2>/dev/null || true
  systemctl disable "code-server@$USERNAME" 2>/dev/null || true
  pkill -9 -u "$USERNAME" 2>/dev/null || true
  userdel -r "$USERNAME"
fi

# ================================
# CREATE USER (SHELL ENABLED, LOGIN LOCKED)
# ================================
useradd -m -s /bin/bash "$USERNAME"
passwd -l "$USERNAME"   # disables password login
chown "$USERNAME:$USERNAME" "/home/$USERNAME"
chmod 700 "/home/$USERNAME"

# ================================
# PROJECTS DIRECTORY
# ================================
PROJECTS_DIR="/home/$USERNAME/Projects"
mkdir -p "$PROJECTS_DIR"
chown "$USERNAME:$USERNAME" "$PROJECTS_DIR"
chmod 700 "$PROJECTS_DIR"

# ================================
# LOCK SSH (READ-ONLY FOR USER)
# ================================
SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
chown root:root "$SSH_DIR"
chmod 555 "$SSH_DIR"

# ================================
# LOCK SHELL PROFILE FILES (READ-ONLY)
# ================================
for file in .bashrc .profile .bash_logout; do
  FILE="/home/$USERNAME/$file"
  [[ -f "$FILE" ]] || touch "$FILE"
  chown root:root "$FILE"
  chmod 444 "$FILE"
done

# ================================
# DENY CRON & AT
# ================================
grep -qxF "$USERNAME" /etc/cron.deny || echo "$USERNAME" >> /etc/cron.deny
grep -qxF "$USERNAME" /etc/at.deny   || echo "$USERNAME" >> /etc/at.deny

# ================================
# RESOURCE LIMITS
# ================================
cat > "/etc/security/limits.d/dev-env-$USERNAME.conf" <<EOF
$USERNAME hard nproc 100
$USERNAME hard nofile 1024
$USERNAME hard fsize 1048576
EOF

# ================================
# LOG
# ================================
echo "$(date '+%F %T') | CREATE_USER | $USERNAME" >> "$LOG_FILE"

echo "✅ User '$USERNAME' created"
echo "📁 Home directory writable by user"
echo "🔒 .bashrc / .profile / .bash_logout read-only"
echo "🔒 .ssh read-only"
echo "🚫 Password login, cron, at disabled"
