#!/usr/bin/env bash
#
# Server Setup Essentials - Installer
# Idempotent installer to fetch and setup the modular Server-Setup-Essentials

set -euo pipefail

# Require root
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR] This script must be run as root.\033[0m"
    exit 1
fi

# Centralized repository configuration
GITHUB_USER="ammasood12"
GITHUB_REPO="Server-Setup-Essentials"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"

# Directory setup
INSTALL_DIR="/opt/sse"
WRAPPER_PATH="/usr/local/bin/sse"

if [[ -d "${INSTALL_DIR}" && -f "${WRAPPER_PATH}" ]]; then
    IS_UPDATE=1
    echo -e "\033[1;36mStarting Server Setup Essentials Update...\033[0m"
else
    IS_UPDATE=0
    echo -e "\033[1;36mStarting Server Setup Essentials Installation...\033[0m"
fi

echo -e "Creating directories..."
mkdir -p "${INSTALL_DIR}"

# Files to download
FILES=(
    "server-setup-essentials.sh"
    "common.sh"
    "display.sh"
    "swap.sh"
    "network.sh"
    "logs.sh"
    "packages.sh"
    "benchmark.sh"
    "hostname.sh"
    "timezone.sh"
)

# Download dependencies (curl)
if ! command -v curl >/dev/null 2>&1; then
    echo -e "Installing curl..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl bash
    fi
fi

# Download files
if [[ $IS_UPDATE -eq 1 ]]; then
    echo -e "Updating files from ${RAW_BASE}..."
else
    echo -e "Downloading files from ${RAW_BASE}..."
fi

for FILE in "${FILES[@]}"; do
    FILE_URL="${RAW_BASE}/${FILE}"
    DEST_PATH="${INSTALL_DIR}/${FILE}"
    
    echo -e "  -> Fetching ${FILE}..."
    if ! curl -fsSL "$FILE_URL" -o "$DEST_PATH"; then
        echo -e "\033[0;33m[WARN] Failed to download ${FILE}. If you are developing locally, ensure the file is pushed to the repository.\033[0m"
    fi
done

# Set permissions
echo -e "Setting permissions..."
chmod -R +x "${INSTALL_DIR}"

# Global command wrapper
if [[ $IS_UPDATE -eq 0 ]]; then
    echo -e "Creating global command at ${WRAPPER_PATH}..."
    cat <<EOF > "${WRAPPER_PATH}"
#!/usr/bin/env bash
exec "${INSTALL_DIR}/server-setup-essentials.sh" "\$@"
EOF
    chmod +x "${WRAPPER_PATH}"
fi

if [[ $IS_UPDATE -eq 1 ]]; then
    echo -e "\033[0;32m[OK] Update complete! Server Setup Essentials is now up to date.\033[0m"
else
    echo -e "\033[0;32m[OK] Installation complete! You can now launch the tool by typing: sse\033[0m"
fi
