#!/bin/bash
set -euo pipefail

USERNAME="$1"
PORT="$2"

if [[ -z "$USERNAME" || -z "$PORT" ]]; then
  echo "Usage: setup-code-server.sh <username> <port>"
  exit 1
fi

# Ask for password
read -s -p "Enter password for $USERNAME: " CODE_PASSWORD
echo

SERVICE_FILE="/etc/systemd/system/code-server@$USERNAME.service"
EXTENSIONS_DIR="/opt/vscode-extensions"

# Ensure extensions dir exists
mkdir -p "$EXTENSIONS_DIR"
chmod 755 "$EXTENSIONS_DIR"

# Create systemd service for this user
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
#MemoryDenyWriteExecute=yes

# ✅ FILESYSTEM ACCESS
ReadWritePaths=/home/$USERNAME
ReadOnlyPaths=/usr/bin/code-server /usr/lib /lib /lib64
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 🚀 START CODE SERVER WITH CONFIG
ExecStart=/usr/bin/code-server \
  --bind-addr 0.0.0.0:$PORT \
  --auth password \
  --password '$CODE_PASSWORD' \
  --disable-file-downloads \
  --disable-file-uploads \
  --extensions-dir $EXTENSIONS_DIR \
  --cert false \
  /home/$USERNAME

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions for service
chmod 644 "$SERVICE_FILE"

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable "code-server@$USERNAME"
systemctl start "code-server@$USERNAME"

echo "Code-server started for $USERNAME on port $PORT with internet access"
