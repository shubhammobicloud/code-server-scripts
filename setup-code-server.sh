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

RUNTIME_DIR="/home/$USERNAME/.local/share/code-server"
CACHE_DIR="/home/$USERNAME/.cache/code-server"

# ================================
# Shared extensions (read-only)
# ================================
mkdir -p "$EXTENSIONS_DIR"
chown root:root "$EXTENSIONS_DIR"
chmod 755 "$EXTENSIONS_DIR"

# ================================
# Config directory (root write)
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
extensions-dir: $EXTENSIONS_DIR
cert: false
EOF

chown root:"$USERNAME" "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"

# ================================
# Runtime directories (user write)
# ================================
mkdir -p "$RUNTIME_DIR" "$CACHE_DIR"
chown -R "$USERNAME:$USERNAME" \
  "/home/$USERNAME/.local" \
  "/home/$USERNAME/.cache"

chmod -R 700 \
  "/home/$USERNAME/.local" \
  "/home/$USERNAME/.cache"

# ================================
# systemd service
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
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictNamespaces=yes
RestrictSUIDSGID=yes
LockPersonality=yes

# ✅ WRITE ONLY WHERE REQUIRED
ReadWritePaths=/home/$USERNAME \
               /home/$USERNAME/.local \
               /home/$USERNAME/.cache

ReadOnlyPaths=/opt/vscode-extensions

Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 🚀 START
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
echo "🔒 Config locked: $CONFIG_FILE"
echo "👤 User = read-only config | 👑 Root = full control"
