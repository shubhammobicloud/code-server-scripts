#!/bin/bash
set -euo pipefail

USERNAME="${1:-}"

if [[ -z "$USERNAME" ]]; then
  echo "Usage: $0 <username>"
  exit 1
fi

if ! id "$USERNAME" &>/dev/null; then
  echo "❌ User $USERNAME does not exist"
  exit 1
fi

# ================================
# PATHS
# ================================
WRAPPER_DIR="/usr/local/bin/git-wrappers"
USER_WRAPPER="$WRAPPER_DIR/git-$USERNAME"
GLOBAL_GIT_SHIM="/usr/local/bin/git"
SSH_KEY="/etc/git-ssh/deploy_key"

# ================================
# CREATE WRAPPER DIR
# ================================
mkdir -p "$WRAPPER_DIR"
chown root:root "$WRAPPER_DIR"
chmod 755 "$WRAPPER_DIR"

# ================================
# CREATE PER-USER WRAPPER
# ================================
cat > "$USER_WRAPPER" <<EOF
#!/bin/bash
set -e

SSH_KEY="$SSH_KEY"
TARGET_USER="$USERNAME"
TARGET_GROUP="$USERNAME"

ALLOWED_CMDS=("fetch" "clone" "status" "pull" "push" "branch" "checkout" "switch" "add" "commit" "config" "restore")

URL_WHITELIST=(
  "https://github.com/shubhammobicloud/testrepo.git"
  "https://github.com/vikrant29k/SmartWork-Admin.git"
  "https://gitlab.com/myteam/anotherrepo.git"
  "http://gitlab.com/myteam/anotherrepo.git"
)

CMD="\$1"

is_http_allowed() {
  local url="\$1"
  [[ "\$url" != http://* && "\$url" != https://* ]] && return 0
  for ALLOW in "\${URL_WHITELIST[@]}"; do
    [[ "\$url" == "\$ALLOW" ]] && return 0
  done
  return 1
}

# Block non-whitelisted HTTP URLs
for ARG in "\$@"; do
  if [[ "\$ARG" == http://* || "\$ARG" == https://* ]]; then
    if ! is_http_allowed "\$ARG"; then
      echo "❌ HTTP/HTTPS Git URL blocked"
      printf ' - %s\n' "\${URL_WHITELIST[@]}"
      exit 1
    fi
  fi
done

# Command allowlist
if [[ ! " \${ALLOWED_CMDS[*]} " =~ " \$CMD " ]]; then
  echo "❌ git command '\$CMD' is not allowed"
  exit 1
fi

# Restrict git config
if [[ "\$CMD" == "config" ]]; then
  case "\$2" in
    user.name|user.email) ;;
    --global)
      [[ "\$3" == "user.name" || "\$3" == "user.email" || ( "\$3" == "--add" && "\$4" == "safe.directory" ) ]] || {
        echo "❌ Only user.name, user.email, safe.directory allowed"
        exit 1
      }
      ;;
    *)
      echo "❌ Only user.name, user.email, safe.directory allowed"
      exit 1
      ;;
  esac
fi

# Execute git as root with SSH key
sudo -u root env \
  GIT_SSH_COMMAND="ssh -i \$SSH_KEY -o StrictHostKeyChecking=no" \
  /usr/bin/git "\$@"

# Fix ownership after clone
if [[ "\$CMD" == "clone" ]]; then
  CLONE_DIR="\${3:-\$(basename "\$2" .git)}"
  chown -R "\$TARGET_USER:\$TARGET_GROUP" "\$PWD/\$CLONE_DIR"
fi
EOF

chmod 755 "$USER_WRAPPER"
chown root:root "$USER_WRAPPER"

# ================================
# CREATE GLOBAL GIT SHIM (ONCE)
# ================================
if [[ ! -f "$GLOBAL_GIT_SHIM" ]]; then
  cat > "$GLOBAL_GIT_SHIM" <<'EOF'
#!/bin/bash
exec sudo /usr/local/bin/git-wrappers/git-$USER "$@"
EOF

  chmod 755 "$GLOBAL_GIT_SHIM"
  chown root:root "$GLOBAL_GIT_SHIM"
fi

# ================================
# BLOCK SYSTEM GIT FOR USERS
# ================================
chmod 700 /usr/bin/git
chown root:root /usr/bin/git

echo "✅ Git wrapper installed for user: $USERNAME"
echo "➡ git → /usr/local/bin/git → $USER_WRAPPER"
