#!/bin/bash
#
# Kiosk-Apps Sync and Update Script
# Runs on every boot to check for updates and apply them
#
# This script:
# 1. Pulls latest changes from git
# 2. Applies configuration updates to kiosk
# 3. Runs package updates if specified
# 4. Restarts services if needed
#

set -euo pipefail

# Configuration
REPO_DIR="/opt/kiosk-apps"
REPO_URL="https://github.com/ai5x/kiosk-apps.git"
LOG_FILE="/var/log/kiosk-apps-sync.log"
KIOSK_DIR="/opt/kiosk"
KIOSK_CONFIG="${KIOSK_DIR}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo "==========================================" | tee -a "$LOG_FILE"
    echo "$1" | tee -a "$LOG_FILE"
    echo "==========================================" | tee -a "$LOG_FILE"
}

# Main sync and update logic
main() {
    # Ensure log file exists and is writable
    if ! touch "$LOG_FILE" 2>/dev/null; then
        echo "ERROR: Cannot write to log file: $LOG_FILE" >&2
        echo "This script must be run as root or with appropriate permissions" >&2
        exit 1
    fi

    # Console startup message
    echo ""
    echo "========================================================"
    echo "  KIOSK-APPS AUTO-UPDATE"
    echo "========================================================"
    echo "  Checking for configuration updates..."
    echo "========================================================"
    echo ""

    log_section "Kiosk-Apps Auto-Update"
    log_info "Starting sync and update process..."

    # Verify running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Check if repo directory exists, if not try to clone
    if [ ! -d "$REPO_DIR" ]; then
        log_warn "Repository directory not found: $REPO_DIR"
        log_info "Attempting to clone repository for auto-recovery..."

        # Check network connectivity before attempting clone
        if ! timeout 5 curl -sf https://github.com >/dev/null 2>&1; then
            log_error "GitHub unreachable - cannot clone repository"
            log_error "Kiosk will continue with default configuration"
            log_error "Repository will be cloned on next boot when network is available"
            exit 0
        fi

        # Try to clone the repository
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            REPO_URL_WITH_TOKEN=$(echo "$REPO_URL" | sed "s|https://|https://${GITHUB_TOKEN}@|")
            if timeout 60 git clone "$REPO_URL_WITH_TOKEN" "$REPO_DIR" 2>&1 | tee -a "$LOG_FILE"; then
                log_info "✓ Repository cloned successfully"
            else
                log_error "Failed to clone repository with token"
                log_error "Kiosk will continue with default configuration"
                exit 0
            fi
        else
            if timeout 60 git clone "$REPO_URL" "$REPO_DIR" 2>&1 | tee -a "$LOG_FILE"; then
                log_info "✓ Repository cloned successfully"
            else
                log_error "Failed to clone repository (repo may be private - set GITHUB_TOKEN)"
                log_error "Kiosk will continue with default configuration"
                exit 0
            fi
        fi
    fi

    cd "$REPO_DIR"

    # Check if git repo
    if [ ! -d ".git" ]; then
        log_warn "Not a git repository - running apply-updates anyway..."
        exec "${REPO_DIR}/scripts/apply-updates.sh"
    fi

    # Check for network connectivity
    if ! timeout 5 curl -sf https://github.com >/dev/null 2>&1; then
        log_warn "GitHub unreachable - skipping git pull"
        log_info "Continuing with current version..."
        exec "${REPO_DIR}/scripts/apply-updates.sh"
    fi

    # Get current commit before pull
    CURRENT_COMMIT=$(git rev-parse HEAD)
    log_info "Current commit: ${CURRENT_COMMIT:0:8}"

    # Fetch latest changes (using token if available)
    log_info "Fetching latest changes from $REPO_URL..."
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        REPO_URL_WITH_TOKEN=$(echo "$REPO_URL" | sed "s|https://|https://${GITHUB_TOKEN}@|")
        if timeout 30 git fetch "$REPO_URL_WITH_TOKEN" master 2>&1 | tee -a "$LOG_FILE"; then
            log_info "✓ Fetch successful (using token)"
        else
            log_warn "Fetch failed - continuing with current version"
            exec "${REPO_DIR}/scripts/apply-updates.sh"
        fi
    else
        if timeout 30 git fetch origin master 2>&1 | tee -a "$LOG_FILE"; then
            log_info "✓ Fetch successful"
        else
            log_warn "Fetch failed - continuing with current version"
            exec "${REPO_DIR}/scripts/apply-updates.sh"
        fi
    fi

    # Check if there are updates
    REMOTE_COMMIT=$(git rev-parse origin/master)
    log_info "Remote commit: ${REMOTE_COMMIT:0:8}"

    if [ "$CURRENT_COMMIT" = "$REMOTE_COMMIT" ]; then
        log_info "✓ Already up to date"
    else
        log_info "Updates available - pulling changes..."
        if git reset --hard origin/master 2>&1 | tee -a "$LOG_FILE"; then
            NEW_COMMIT=$(git rev-parse HEAD)
            log_info "✓ Updated to commit: ${NEW_COMMIT:0:8}"
            log_info "Changes:"
            git log --oneline --no-decorate "${CURRENT_COMMIT}..${NEW_COMMIT}" | tee -a "$LOG_FILE"
        else
            log_error "Failed to update - rolling back"
            git reset --hard "$CURRENT_COMMIT" 2>&1 | tee -a "$LOG_FILE"
        fi
    fi

    # Execute apply-updates.sh to apply configuration changes
    log_section "Applying Updates"
    log_info "Running apply-updates.sh to apply configuration and package updates..."

    echo ""
    echo ">>> Applying kiosk configuration updates..."
    echo ""

    exec "${REPO_DIR}/scripts/apply-updates.sh"
}

# Run main function
main "$@"
