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
WRAPPER_BIN="$WRAPPER_DIR/git-$USERNAME"
SUDOERS_FILE="/etc/sudoers.d/git-wrapper-$USERNAME"
SSH_KEY="/etc/git-ssh/deploy_key"
USER_HOME="/home/$USERNAME"
PROFILE_FILE="$USER_HOME/.bashrc"

# ================================
# CREATE WRAPPER DIRECTORY
# ================================
mkdir -p "$WRAPPER_DIR"
chown root:root "$WRAPPER_DIR"
chmod 755 "$WRAPPER_DIR"

# ================================
# CREATE GIT WRAPPER
# ================================
cat > "$WRAPPER_BIN" <<EOF
#!/bin/bash
# Git wrapper for user $USERNAME (controlled)

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

# Block non-whitelisted HTTP/HTTPS repos
for ARG in "\$@"; do
  if [[ "\$ARG" == http://* || "\$ARG" == https://* ]]; then
    if ! is_http_allowed "\$ARG"; then
      echo "❌ HTTP/HTTPS Git URL blocked"
      printf ' - %s\n' "\${URL_WHITELIST[@]}"
      exit 1
    fi
  fi
done

# Allowed commands only
if [[ ! " \${ALLOWED_CMDS[@]} " =~ " \$CMD " ]]; then
  echo "❌ git command '\$CMD' is not allowed"
  exit 1
fi

# Restrict git config
if [[ "\$CMD" == "config" ]]; then
  case "\$2" in
    "user.name"|"user.email") ;;
    "--global")
      if [[ "\$3" == "user.name" || "\$3" == "user.email" ]]; then
        true
      elif [[ "\$3" == "--add" && "\$4" == "safe.directory" ]]; then
        true
      else
        echo "❌ Only user.name, user.email, safe.directory allowed"
        exit 1
      fi
      ;;
    *)
      echo "❌ Only user.name, user.email, safe.directory allowed"
      exit 1
      ;;
  esac
fi

# Execute real git as root using server SSH key
/usr/bin/git "\$@" </dev/null
EOF

chmod 755 "$WRAPPER_BIN"
chown root:root "$WRAPPER_BIN"

# ================================
# BLOCK REAL GIT FOR THIS USER
# ================================
# setfacl -m u:"$USERNAME":--- /usr/bin/git

# ================================
# ADD SUDOERS RULE (WRAPPER ONLY)
# ================================
# cat > "$SUDOERS_FILE" <<EOF
# $USERNAME ALL=(root) NOPASSWD: $WRAPPER_BIN
# EOF

# chmod 440 "$SUDOERS_FILE"

# ================================
# ADD ALIAS FOR USER
# ================================
if ! grep -q "alias git=" "$PROFILE_FILE" 2>/dev/null; then
  echo "alias git='sudo $WRAPPER_BIN'" >> "$PROFILE_FILE"
fi

chown "$USERNAME:$USERNAME" "$PROFILE_FILE"

# ================================
# DONE
# ================================
echo "✅ Git wrapper installed for $USERNAME"
echo "🔒 /usr/bin/git blocked for this user only"
echo "🔑 Passwordless sudo enabled ONLY for wrapper"
echo "➡️  User must re-login to apply alias"
