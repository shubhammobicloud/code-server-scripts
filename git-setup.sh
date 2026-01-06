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
SSH_KEY="/etc/git-ssh/deploy_key"

# ================================
# CREATE WRAPPER DIRECTORY
# ================================
mkdir -p "$WRAPPER_DIR"
chown root:root "$WRAPPER_DIR"
chmod 755 "$WRAPPER_DIR"

# ================================
# CREATE GIT WRAPPER
# ================================
cat > "$WRAPPER_BIN" <<'EOF'
#!/bin/bash
# Git wrapper for user $USERNAME using server SSH key

SSH_KEY="/etc/git-ssh/deploy_key"
TARGET_USER="$USERNAME"
TARGET_GROUP="$USERNAME"

ALLOWED_CMDS=("fetch" "clone" "status" "pull" "push" "branch" "checkout" "switch" "add" "commit" "config" "restore")
URL_WHITELIST=(
    "https://github.com/shubhammobicloud/testrepo.git"
    "https://github.com/vikrant29k/SmartWork-Admin.git"
    "https://gitlab.com/myteam/anotherrepo.git"
    "http://gitlab.com/myteam/anotherrepo.git"
)

CMD="$1"

is_http_allowed() {
    local url="$1"
    [[ "$url" != http://* && "$url" != https://* ]] && return 0
    for ALLOW in "${URL_WHITELIST[@]}"; do
        [[ "$url" == "$ALLOW" ]] && return 0
    done
    return 1
}

for ARG in "$@"; do
    if [[ "$ARG" == http://* || "$ARG" == https://* ]]; then
        if ! is_http_allowed "$ARG"; then
            echo "Error: HTTP/HTTPS Git URL blocked. Allowed only:"
            printf ' - %s\n' "${URL_WHITELIST[@]}"
            exit 1
        fi
    fi
done

if [[ ! " ${ALLOWED_CMDS[@]} " =~ " $CMD " ]]; then
    echo "Error: git command '$CMD' is not allowed"
    exit 1
fi

if [[ "$CMD" == "config" ]]; then
    case "$2" in
        "user.name"|"user.email") true ;;
        "--global")
            if [[ "$3" == "user.name" || "$3" == "user.email" ]]; then true
            elif [[ "$3" == "--add" && "$4" == "safe.directory" ]]; then true
            else echo "Error: Only user.name, user.email, safe.directory allowed"; exit 1
            fi
            ;;
        *) echo "Error: Only user.name, user.email, safe.directory allowed"; exit 1 ;;
    esac
fi

# Execute git with server SSH key
sudo -u root env GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=no" git "$@"
GIT_EXIT_CODE=$?

if [[ $GIT_EXIT_CODE -ne 0 ]]; then
    exit $GIT_EXIT_CODE
fi

CURRENT_DIR=$(pwd)
if [[ "$CMD" == "clone" ]]; then
    if [[ -n "$3" ]]; then
        CLONE_DIR="$3"
    else
        CLONE_DIR=$(basename "$2" .git)
    fi
    CURRENT_DIR="$CURRENT_DIR/$CLONE_DIR"
fi

chown -R "$TARGET_USER:$TARGET_GROUP" "$CURRENT_DIR"
exit 0
EOF

chmod 755 "$WRAPPER_BIN"
chown root:root "$WRAPPER_BIN"

# ================================
# ADD ALIAS TO USER SHELL
# ================================
PROFILE_FILE="/home/$USERNAME/.bashrc"
if ! grep -q "alias git=" "$PROFILE_FILE" 2>/dev/null; then
    echo "alias git='sudo $WRAPPER_BIN'" >> "$PROFILE_FILE"
fi

# ================================
# INFO
# ================================
echo "✅ Git wrapper created for user $USERNAME"
echo "📁 Wrapper path: $WRAPPER_BIN"
echo "⚠️  User $USERNAME will now use 'git' alias pointing to this wrapper"
echo "⚠️  Original git binary remains unchanged for other users"
