#!/bin/bash
set -euo pipefail

LOG_DIR="/opt/dev-env/logs"
LOG_FILE="$LOG_DIR/actions.log"

USERNAME="${1:-}"

if [[ -z "$USERNAME" ]]; then
  read -p "Enter username to DELETE: " USERNAME
fi

# ================================
# VALIDATION
# ================================
if [[ "$USERNAME" == "root" ]]; then
  echo "❌ Refusing to delete root"
  exit 1
fi

if [[ ! "$USERNAME" =~ ^[a-z0-9_]{3,16}$ ]]; then
  echo "❌ Invalid username"
  exit 1
fi

if ! id "$USERNAME" &>/dev/null; then
  echo "❌ User '$USERNAME' does not exist"
  exit 1
fi

# ================================
# FINAL CONFIRMATION
# ================================
echo "⚠️  This will permanently delete:"
echo "   - User: $USERNAME"
echo "   - Home directory"
echo "   - code-server service"
echo "   - Git wrapper and alias"
echo "   - All configs & limits"
echo
read -p "Type the username to confirm deletion: " CONFIRM

if [[ "$CONFIRM" != "$USERNAME" ]]; then
  echo "❌ Confirmation failed. Aborting."
  exit 1
fi

# ================================
# STOP & REMOVE CODE-SERVER SERVICE
# ================================
SERVICE="code-server@$USERNAME"

systemctl stop "$SERVICE" 2>/dev/null || true
systemctl disable "$SERVICE" 2>/dev/null || true
rm -f "/etc/systemd/system/$SERVICE.service"

# ================================
# KILL USER PROCESSES
# ================================
pkill -9 -u "$USERNAME" 2>/dev/null || true

# ================================
# REMOVE CODE-SERVER DATA
# ================================
rm -rf "/home/$USERNAME/.config/code-server"
rm -rf "/home/$USERNAME/.local/share/code-server"
rm -rf "/home/$USERNAME/.cache/code-server"
rm -rf "/home/$USERNAME/.code-server-data"
rm -rf "/home/$USERNAME/Projects"

# ================================
# REMOVE LIMITS
# ================================
rm -f "/etc/security/limits.d/dev-env-$USERNAME.conf"

# ================================
# REMOVE CRON / AT DENY
# ================================
sed -i "/^$USERNAME$/d" /etc/cron.deny
sed -i "/^$USERNAME$/d" /etc/at.deny

# ================================
# REMOVE GIT WRAPPER & ALIAS
# ================================
WRAPPER_BIN="/usr/local/bin/git-$USERNAME"
if [[ -f "$WRAPPER_BIN" ]]; then
    rm -f "$WRAPPER_BIN"
fi

PROFILE_FILE="/home/$USERNAME/.bashrc"
if [[ -f "$PROFILE_FILE" ]]; then
    sed -i "/alias git=.*git-$USERNAME/d" "$PROFILE_FILE"
fi

# ================================
# DELETE USER & HOME
# ================================
userdel -r "$USERNAME"

# ================================
# SYSTEMD RELOAD
# ================================
systemctl daemon-reload

# ================================
# LOG ACTION
# ================================
mkdir -p "$LOG_DIR"
echo "$(date '+%F %T') | DELETE_USER | $USERNAME" >> "$LOG_FILE"

echo "🗑️  User '$USERNAME' and all related resources deleted successfully"
