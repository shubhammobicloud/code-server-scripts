#!/bin/bash
set -euo pipefail

USERNAME="$1"
PORT="$2"

if [[ -z "$USERNAME" || -z "$PORT" ]]; then
  echo "Usage: $0 <username> <port>"
  exit 1
fi

# Ask for code-server password
read -s -p "Enter code-server password for $USERNAME: " CODE_PASSWORD
echo

SERVICE_FILE="/etc/systemd/system/code-server@$USERNAME.service"
EXTENSIONS_DIR="/opt/vscode-extensions"
CONFIG_DIR="/home/$USERNAME/.config/code-server"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

# Create extensions directory
mkdir -p "$EXTENSIONS_DIR"
chmod 755 "$EXTENSIONS_DIR"

# Create config directory as root (dev user cannot modify)
mkdir -p "$CONFIG_DIR"
chown root:root "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

# Create config.yaml as root
tee "$CONFIG_FILE" > /dev/null <<EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $CODE_PASSWORD
disable-file-downloads: true
disable-file-uploads: true
extensions-dir: $EXTENSIONS_DIR
cert: false
EOF

# Lock config file permissions (admin only)
chown root:root "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

# Create systemd service
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Code Server for $USERNAME
After=network.target

[Service]
Type=simple
User=$USERNAME
Group=$USERNAME

# 🔒 SANDBOX OPTIONS
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

# ✅ FILESYSTEM ACCESS
ReadWritePaths=/home/$USERNAME
ReadOnlyPaths=/usr/bin/code-server /usr/lib /lib /lib64
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 🚀 START CODE SERVER
ExecStart=/usr/bin/code-server /home/$USERNAME

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Permissions for systemd service
chmod 644 "$SERVICE_FILE"

# Reload systemd, enable and start
systemctl daemon-reload
systemctl enable "code-server@$USERNAME"
systemctl start "code-server@$USERNAME"

echo "Code-server started for $USERNAME on port $PORT with internet access"
echo "Config file is admin-only (read-only for $USERNAME)"
