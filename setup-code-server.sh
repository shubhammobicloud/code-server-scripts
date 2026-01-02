#!/bin/bash
set -euo pipefail

USERNAME="${1:-}"
PORT="${2:-}"

if [[ -z "$USERNAME" || -z "$PORT" ]]; then
  echo "Usage: $0 <username> <port>"
  exit 1
fi

# Ask for code-server password
read -s -p "Enter code-server password for $USERNAME: " CODE_PASSWORD
echo

SERVICE_FILE="/etc/systemd/system/code-server@$USERNAME.service"
EXTENSIONS_DIR="/opt/vscode-extensions"
CONFIG_DIR="/etc/code-server"
CONFIG_FILE="$CONFIG_DIR/$USERNAME.yaml"

# Ensure user exists
if ! id "$USERNAME" &>/dev/null; then
  echo "❌ User $USERNAME does not exist"
  exit 1
fi

# Create admin-only config directory
mkdir -p "$CONFIG_DIR"
chown root:root "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

# Create extensions directory (shared, read-only)
mkdir -p "$EXTENSIONS_DIR"
chown root:root "$EXTENSIONS_DIR"
chmod 755 "$EXTENSIONS_DIR"

# Create config file (admin-only)
tee "$CONFIG_FILE" > /dev/null <<EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $CODE_PASSWORD
disable-file-downloads: true
disable-file-uploads: true
extensions-dir: $EXTENSIONS_DIR
cert: false
EOF

chown root:root "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

# Create systemd service
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

# ✅ ALLOW WORKSPACE ONLY
ReadWritePaths=/home/$USERNAME
ReadOnlyPaths=/etc/code-server /opt/vscode-extensions

Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 🚀 START CODE SERVER WITH ADMIN CONFIG
ExecStart=/usr/bin/code-server \
  --config /etc/code-server/$USERNAME.yaml \
  /home/$USERNAME

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"

# Reload and start
systemctl daemon-reload
systemctl enable "code-server@$USERNAME"
systemctl restart "code-server@$USERNAME"

echo "✅ Code-server running for $USERNAME on port $PORT"
echo "🔒 Config locked at $CONFIG_FILE (admin-only)"
