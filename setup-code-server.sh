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

# ================================
# PASSWORD INPUT
# ================================
read -s -p "Enter code-server password: " CODE_PASSWORD
echo

# ================================
# PATHS
# ================================
SERVICE_FILE="/etc/systemd/system/code-server@$USERNAME.service"

HOME_DIR="/home/$USERNAME"
PROJECTS_DIR="$HOME_DIR/Projects"

USER_DATA_DIR="$HOME_DIR/.code-server-data"
CONFIG_DIR="$HOME_DIR/.config/code-server"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

EXT_DIR="/opt/vscode-extensions"
EXTENSIONS_JSON="$EXT_DIR/extensions.json"

BLOCKER_DIR="/opt/bin-blocker"
BLOCKER_BIN="$BLOCKER_DIR/blocked"

# ================================
# CREATE PROJECTS DIR
# ================================
mkdir -p "$PROJECTS_DIR"
chown "$USERNAME:$USERNAME" "$PROJECTS_DIR"
chmod 700 "$PROJECTS_DIR"

# ================================
# SHARED EXTENSIONS (READ-ONLY)
# ================================
mkdir -p "$EXT_DIR"
touch "$EXTENSIONS_JSON"
chown -R root:root "$EXT_DIR"
chmod 755 "$EXT_DIR"
chmod 644 "$EXTENSIONS_JSON"

# ================================
# USER DATA DIR (SETTINGS)
# ================================
mkdir -p "$USER_DATA_DIR"
chown "$USERNAME:$USERNAME" "$USER_DATA_DIR"
chmod 700 "$USER_DATA_DIR"

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
extensions-dir: $EXT_DIR
disable-file-downloads: true
disable-file-uploads: true
cert: false
EOF

chown root:"$USERNAME" "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"

# ================================
# CREATE BLOCKER BINARY
# ================================
mkdir -p "$BLOCKER_DIR"

cat > "$BLOCKER_BIN" <<'EOF'
#!/bin/bash
echo "❌ This command is disabled in this development environment."
exit 1
EOF

chmod 755 "$BLOCKER_BIN"
chown root:root "$BLOCKER_BIN"

# ================================
# BLOCK GIT FOR THIS USER ONLY
# ================================
GIT_BIN="$(which git)"
if [[ -f "$GIT_BIN" ]]; then
  setfacl -m u:"$USERNAME":--- "$GIT_BIN"
fi

# ================================
# SYSTEMD SERVICE
# ================================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Code Server for $USERNAME
After=network.target

[Service]
Type=simple
User=$USERNAME
Group=$USERNAME

# 🔐 HARDENING
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

# ✅ WRITE ACCESS
ReadWritePaths=$PROJECTS_DIR $USER_DATA_DIR

# 🔒 SHARED EXTENSIONS
ReadOnlyPaths=$EXT_DIR

# 🚫 BLOCK DANGEROUS BINARIES (SERVICE ONLY)
BindPaths=$BLOCKER_BIN:/usr/bin/curl
BindPaths=$BLOCKER_BIN:/usr/bin/wget
BindPaths=$BLOCKER_BIN:/usr/bin/scp
BindPaths=$BLOCKER_BIN:/usr/bin/rsync
BindPaths=$BLOCKER_BIN:/usr/bin/nc
BindPaths=$BLOCKER_BIN:/usr/bin/ncat
BindPaths=$BLOCKER_BIN:/usr/bin/ftp
BindPaths=$BLOCKER_BIN:/usr/bin/sftp
BindPaths=$BLOCKER_BIN:/usr/bin/telnet
BindPaths=$BLOCKER_BIN:/usr/bin/ssh
BindPaths=$BLOCKER_BIN:/usr/bin/ping
BindPaths=$BLOCKER_BIN:/usr/bin/traceroute
BindPaths=$BLOCKER_BIN:/usr/bin/dig
BindPaths=$BLOCKER_BIN:/usr/bin/nslookup
BindPaths=$BLOCKER_BIN:/usr/bin/mount
BindPaths=$BLOCKER_BIN:/usr/bin/umount
BindPaths=$BLOCKER_BIN:/usr/bin/su
BindPaths=$BLOCKER_BIN:/usr/bin/sudo
BindPaths=$BLOCKER_BIN:/usr/bin/chown

Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 🚀 START (OPEN PROJECTS ONLY)
ExecStart=/usr/bin/code-server \
  --user-data-dir=$USER_DATA_DIR \
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
echo "📁 Workspace: $PROJECTS_DIR"
echo "🚫 Dangerous binaries blocked for this service (ssh, curl, wget, scp, rsync, ping, etc.)"
echo "🚫 Git is blocked for this user only"
