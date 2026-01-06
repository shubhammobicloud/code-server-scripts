#!/bin/bash
set -euo pipefail

USERNAME="${1:-}"
PORT="${2:-}"

if [[ -z "$USERNAME" || -z "$PORT" ]]; then
  echo "Usage: $0 <username> <port>"
  exit 1
fi

if ! id "$USERNAME" &>/dev/null; then
  echo "❌ User does not exist"
  exit 1
fi

PROJECTS_DIR="/home/$USERNAME/Projects"
USER_DATA_DIR="/home/$USERNAME/.code-server-data"

if [[ ! -d "$PROJECTS_DIR" ]]; then
  echo "❌ Projects directory not found: $PROJECTS_DIR"
  exit 1
fi

# ================================
# PASSWORD INPUT
# ================================
read -s -p "Enter code-server password: " CODE_PASSWORD
echo

SERVICE_FILE="/etc/systemd/system/code-server@$USERNAME.service"
EXT_DIR="/opt/vscode-extensions"

CONFIG_DIR="/home/$USERNAME/.config/code-server"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

RUNTIME_DIR="/home/$USERNAME/.local/share/code-server"
CACHE_DIR="/home/$USERNAME/.cache/code-server"

# ================================
# USER DATA DIR (CRITICAL)
# ================================
mkdir -p "$USER_DATA_DIR"
chown "$USERNAME:$USERNAME" "$USER_DATA_DIR"
chmod 700 "$USER_DATA_DIR"

# ================================
# SHARED EXTENSIONS (READ-ONLY)
# ================================
mkdir -p "$EXT_DIR"
chown root:root "$EXT_DIR"
chmod 755 "$EXT_DIR"

# ================================
# CONFIG (ROOT CONTROLLED)
# ================================
mkdir -p "$CONFIG_DIR"
chown root:"$USERNAME" "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $CODE_PASSWORD
disable-file-downloads: true
disable-file-uploads: true
extensions-dir: $EXT_DIR
cert: false
EOF

chown root:"$USERNAME" "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"

# ================================
# RUNTIME DIRS (USER WRITABLE)
# ================================
mkdir -p "$RUNTIME_DIR" "$CACHE_DIR"

chown -R "$USERNAME:$USERNAME" \
  "$PROJECTS_DIR" \
  "$USER_DATA_DIR" \
  "/home/$USERNAME/.local" \
  "/home/$USERNAME/.cache"

chmod -R 700 \
  "$PROJECTS_DIR" \
  "$USER_DATA_DIR" \
  "/home/$USERNAME/.local" \
  "/home/$USERNAME/.cache"

# ================================
# SYSTEMD SERVICE (FIXED)
# ================================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Code Server for $USERNAME
After=network.target

[Service]
User=$USERNAME
Group=$USERNAME
Type=simple

# 🔒 HARDENING
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictNamespaces=yes
RestrictSUIDSGID=yes
LockPersonality=yes

# ✅ ALLOWED WRITE PATHS
ReadWritePaths=$PROJECTS_DIR \
               $USER_DATA_DIR \
               /home/$USERNAME/.local \
               /home/$USERNAME/.cache

ReadOnlyPaths=$EXT_DIR

Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 🚀 CRITICAL FIX
ExecStart=/usr/bin/code-server \
  --user-data-dir $USER_DATA_DIR \
  $PROJECTS_DIR

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"

# ================================
# START SERVICE
# ================================
systemctl daemon-reload
systemctl enable "code-server@$USERNAME"
systemctl restart "code-server@$USERNAME"

echo "✅ code-server running for $USERNAME on port $PORT"
echo "📂 Workspace: $PROJECTS_DIR"
echo "📦 User data: $USER_DATA_DIR"
