#!/bin/bash
#
# Install kiosk-apps-sync systemd service for auto-recovery
# This service runs on every boot to sync with git and apply updates
#
# Usage: sudo ./install-sync-service.sh
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Verify running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    log_error "Please run: sudo $0"
    exit 1
fi

# Configuration
REPO_DIR="/opt/kiosk-apps"
REPO_URL="https://github.com/ai5x/kiosk-apps.git"
SERVICE_FILE="/etc/systemd/system/kiosk-apps-sync.service"

log_info "Installing kiosk-apps-sync service for auto-recovery..."

# Check if repo exists
if [ ! -d "$REPO_DIR" ]; then
    log_warn "Repository not found at $REPO_DIR"
    log_info "Attempting to clone repository..."

    if git clone "$REPO_URL" "$REPO_DIR"; then
        log_info "✓ Repository cloned successfully"
    else
        log_error "Failed to clone repository"
        log_error "Repository may be private - you can set GITHUB_TOKEN environment variable"
        log_error "The service will still be installed and will retry on every boot"
    fi
fi

# Install service file
if [ -d "$REPO_DIR" ] && [ -f "${REPO_DIR}/systemd/kiosk-apps-sync.service" ]; then
    log_info "Installing service from repository..."
    cp "${REPO_DIR}/systemd/kiosk-apps-sync.service" "$SERVICE_FILE"
else
    log_warn "Service file not found in repo, downloading from GitHub..."
    curl -fsSL "https://raw.githubusercontent.com/ai5x/kiosk-apps/master/systemd/kiosk-apps-sync.service" -o "$SERVICE_FILE"
fi

# Reload systemd
log_info "Reloading systemd daemon..."
systemctl daemon-reload

# Enable service
log_info "Enabling service to run on boot..."
systemctl enable kiosk-apps-sync.service

log_info "✓ kiosk-apps-sync service installed successfully"
log_info ""
log_info "Service configuration:"
log_info "  - Runs as: root (required for system changes)"
log_info "  - Runs on: every boot after network is online"
log_info "  - Repository: $REPO_URL"
log_info "  - Auto-recovery: enabled (will clone repo if missing)"
log_info ""
log_info "To manually trigger the service:"
log_info "  sudo systemctl start kiosk-apps-sync.service"
log_info ""
log_info "To check status:"
log_info "  sudo systemctl status kiosk-apps-sync.service"
log_info "  tail -f /var/log/kiosk-apps-sync.log"
log_info ""
log_info "If repository is private, create /etc/kiosk-apps/github-token:"
log_info "  sudo mkdir -p /etc/kiosk-apps"
log_info "  echo 'GITHUB_TOKEN=ghp_yourtoken' | sudo tee /etc/kiosk-apps/github-token"
log_info "  sudo chmod 600 /etc/kiosk-apps/github-token"
