#!/bin/bash
set -euo pipefail

USERNAME="${1:-}"
PORT="${2:-}"

if [[ -z "$USERNAME" || -z "$PORT" ]]; then
  echo "Usage: $0 <username> <port>"
  exit 1
fi

# Ensure user exists
if ! id "$USERNAME" &>/dev/null; then
  echo "❌ User $USERNAME does not exist"
  exit 1
fi

# Ask for code-server password
read -s -p "Enter code-server password for $USERNAME: " CODE_PASSWORD
echo

SERVICE_FILE="/etc/systemd/system/code-server@$USERNAME.service"
EXTENSIONS_DIR="/opt/vscode-extensions"

CONFIG_DIR="/home/$USERNAME/.config/code-server"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

# ================================
# Create shared extensions dir
# ================================
mkdir -p "$EXTENSIONS_DIR"
chown root:root "$EXTENSIONS_DIR"
chmod 755 "$EXTENSIONS_DIR"

# ================================
# Create config directory (root-owned)
# ================================
mkdir -p "$CONFIG_DIR"
chown root:"$USERNAME" "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

# ================================
# Create config.yaml (root-owned, user-readable)
# ================================
cat > "$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $CODE_PASSWORD
disable-file-downloads: true
disable-file-uploads: true
extensions-dir: $EXTENSIONS_DIR
cert: false
EOF

chown root:"$USERNAME" "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"

# ================================
# Create systemd service
# ================================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Code Server for $USERNAME
After=network.target

[Service]
Type=simple
User=$USERNAME
Group=$USERNAME

# 🔒 HARDENING
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictNamespaces=yes
RestrictSUIDSGID=yes
LockPersonality=yes

# ✅ ALLOW REQUIRED PATHS
ReadWritePaths=/home/$USERNAME
ReadOnlyPaths=/opt/vscode-extensions

Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 🚀 START CODE-SERVER (uses ~/.config automatically)
ExecStart=/usr/bin/code-server /home/$USERNAME

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"

# ================================
# Reload & start
# ================================
systemctl daemon-reload
systemctl enable "code-server@$USERNAME"
systemctl restart "code-server@$USERNAME"

echo "✅ Code-server running for $USERNAME on port $PORT"
echo "🔒 Config locked at $CONFIG_FILE"
echo "👤 User can READ config, only root can MODIFY"
