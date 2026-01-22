#!/bin/bash
#
# Kiosk-Apps Apply Updates Script
# Applies configuration and package updates to the kiosk
#
# This script is idempotent and can be run multiple times safely
#

set -euo pipefail

# Configuration
REPO_DIR="/opt/kiosk-apps"
KIOSK_DIR="/opt/kiosk"
KIOSK_CONFIG="${KIOSK_DIR}/.env"
LOG_FILE="/var/log/kiosk-apps-sync.log"

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

# Check if configuration has changed
check_config_changes() {
    if [ ! -f "${REPO_DIR}/config/.env" ]; then
        log_warn "No config/.env in repository"
        return 1
    fi

    if [ ! -f "$KIOSK_CONFIG" ]; then
        log_info "Kiosk config doesn't exist, will create"
        return 0
    fi

    # Compare configs (ignoring comments and empty lines)
    if diff -w <(grep -v '^#\|^$' "${REPO_DIR}/config/.env" | sort) \
             <(grep -v '^#\|^$' "$KIOSK_CONFIG" | sort) >/dev/null 2>&1; then
        return 1  # No changes
    else
        return 0  # Has changes
    fi
}

# Apply configuration updates
apply_config_updates() {
    log_section "Configuration Updates"

    if check_config_changes; then
        log_info "Configuration changes detected"

        # Backup current config
        if [ -f "$KIOSK_CONFIG" ]; then
            cp "$KIOSK_CONFIG" "${KIOSK_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
            log_info "Backed up current config"
        fi

        # Copy new config
        cp "${REPO_DIR}/config/.env" "$KIOSK_CONFIG"
        chown root:root "$KIOSK_CONFIG"
        chmod 644 "$KIOSK_CONFIG"
        log_info "✓ Applied new configuration"

        # Log what changed
        log_info "Configuration changes:"
        diff -u "${KIOSK_CONFIG}.backup."* "$KIOSK_CONFIG" | tail -n +3 | grep '^[-+]' | tee -a "$LOG_FILE" || true

        return 0  # Config changed, need restart
    else
        log_info "✓ Configuration unchanged"
        return 1  # No restart needed
    fi
}

# Apply script updates
apply_script_updates() {
    log_section "Script Updates"

    local restart_needed=0

    # Update start-kiosk.sh if changed
    if [ -f "${REPO_DIR}/scripts/start-kiosk.sh" ]; then
        if ! diff -q "${REPO_DIR}/scripts/start-kiosk.sh" "${KIOSK_DIR}/start-kiosk.sh" >/dev/null 2>&1; then
            log_info "start-kiosk.sh updated"
            cp "${REPO_DIR}/scripts/start-kiosk.sh" "${KIOSK_DIR}/start-kiosk.sh"
            chmod +x "${KIOSK_DIR}/start-kiosk.sh"
            restart_needed=1
        fi
    fi

    # Update watchdog.sh if changed
    if [ -f "${REPO_DIR}/scripts/watchdog.sh" ]; then
        if ! diff -q "${REPO_DIR}/scripts/watchdog.sh" "${KIOSK_DIR}/watchdog.sh" >/dev/null 2>&1; then
            log_info "watchdog.sh updated"
            cp "${REPO_DIR}/scripts/watchdog.sh" "${KIOSK_DIR}/watchdog.sh"
            chmod +x "${KIOSK_DIR}/watchdog.sh"
            systemctl restart kiosk-watchdog.service
            log_info "✓ Restarted watchdog service"
        fi
    fi

    if [ $restart_needed -eq 0 ]; then
        log_info "✓ Scripts unchanged"
    fi

    return $restart_needed
}

# Apply package updates
apply_package_updates() {
    log_section "Package Updates"

    local packages_changed=0

    # Check if package installation is requested
    if [ -f "${REPO_DIR}/config/install-packages.txt" ]; then
        log_info "Package installation requested"

        # Read packages to install (skip comments and empty lines)
        PACKAGES=$(grep -v '^#' "${REPO_DIR}/config/install-packages.txt" | grep -v '^$' | xargs)

        if [ -n "$PACKAGES" ]; then
            log_info "Installing packages: $PACKAGES"

            # Update package lists
            log_info "Updating package lists..."
            if apt-get update 2>&1 | tee -a "$LOG_FILE"; then
                log_info "✓ Package lists updated"
            else
                log_warn "Failed to update package lists"
                return 1
            fi

            # Install packages
            if DEBIAN_FRONTEND=noninteractive apt-get install -y $PACKAGES 2>&1 | tee -a "$LOG_FILE"; then
                log_info "✓ Packages installed: $PACKAGES"
                packages_changed=1
            else
                log_error "Package installation failed"
                return 1
            fi
        else
            log_info "✓ No packages to install"
        fi
    fi

    # Check if package updates are requested
    if [ -f "${REPO_DIR}/config/update-packages.txt" ]; then
        log_info "Package update requested"

        # Update package lists if not already done
        if [ $packages_changed -eq 0 ]; then
            log_info "Updating package lists..."
            if apt-get update 2>&1 | tee -a "$LOG_FILE"; then
                log_info "✓ Package lists updated"
            else
                log_warn "Failed to update package lists"
                return 1
            fi
        fi

        # Upgrade packages
        log_info "Upgrading packages (this may take a while)..."
        if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y 2>&1 | tee -a "$LOG_FILE"; then
            log_info "✓ Packages upgraded"

            # Remove the update request file
            rm -f "${REPO_DIR}/config/update-packages.txt"
            log_info "Removed update-packages.txt"

            # Create marker for reboot if needed
            if [ -f /var/run/reboot-required ]; then
                log_warn "Reboot required after package updates"
                touch /var/run/kiosk-reboot-required
            fi
        else
            log_error "Package upgrade failed"
            return 1
        fi
    else
        if [ $packages_changed -eq 0 ]; then
            log_info "✓ No package updates requested"
        fi
    fi

    return 0
}

# Restart kiosk if needed
restart_kiosk_if_needed() {
    local config_changed=$1
    local scripts_changed=$2

    if [ $config_changed -eq 0 ] || [ $scripts_changed -eq 0 ]; then
        log_section "Restarting Kiosk"
        log_info "Configuration or scripts changed - restarting display manager..."

        # Give time for any pending operations
        sleep 2

        # Restart display manager (which will restart kiosk)
        systemctl restart lightdm
        log_info "✓ Display manager restarted"

        log_info "Kiosk should now be running with updated configuration"
    else
        log_info "✓ No restart needed"
    fi
}

# Check for reboot requirement
check_reboot_requirement() {
    if [ -f /var/run/kiosk-reboot-required ]; then
        log_section "Reboot Required"
        log_warn "System reboot is required due to package updates"
        log_warn "Reboot will occur in 60 seconds..."
        log_warn "To cancel: rm /var/run/kiosk-reboot-required"

        # Wait 60 seconds to allow logs to be read
        sleep 60

        if [ -f /var/run/kiosk-reboot-required ]; then
            log_info "Rebooting system..."
            rm /var/run/kiosk-reboot-required
            reboot
        else
            log_info "Reboot cancelled by user"
        fi
    fi
}

# Apply display configuration updates
apply_display_config() {
    log_section "Display Configuration"

    local restart_needed=1

    # Read orientation from config
    if [ ! -f "${REPO_DIR}/config/.env" ]; then
        log_warn "No config/.env found, skipping display config"
        return 1
    fi

    source "${REPO_DIR}/config/.env"
    ORIENTATION=${DISPLAY_ORIENTATION:-landscape}
    log_info "Target orientation: $ORIENTATION"

    # Deploy X server config for modesetting driver
    if [ -f "${REPO_DIR}/config/xorg-modesetting.conf" ]; then
        mkdir -p /etc/X11/xorg.conf.d
        if ! diff -q "${REPO_DIR}/config/xorg-modesetting.conf" "/etc/X11/xorg.conf.d/99-v3d.conf" >/dev/null 2>&1; then
            log_info "Updating X server configuration..."
            cp "${REPO_DIR}/config/xorg-modesetting.conf" "/etc/X11/xorg.conf.d/99-v3d.conf"
            chmod 644 /etc/X11/xorg.conf.d/99-v3d.conf
            restart_needed=0
        else
            log_info "✓ X server config unchanged"
        fi
    fi

    # Deploy openbox autostart based on orientation
    local autostart_source="${REPO_DIR}/config/openbox-autostart-${ORIENTATION}"
    local autostart_dest="/home/pi/.config/openbox/autostart"

    if [ ! -f "$autostart_source" ]; then
        log_error "Autostart file not found: $autostart_source"
        log_error "Valid orientations: landscape, portrait, portrait-inverted"
        return 1
    fi

    if ! diff -q "$autostart_source" "$autostart_dest" >/dev/null 2>&1; then
        log_info "Updating openbox autostart for ${ORIENTATION} mode..."
        mkdir -p /home/pi/.config/openbox
        cp "$autostart_source" "$autostart_dest"
        chmod +x "$autostart_dest"
        chown -R pi:pi /home/pi/.config
        log_info "✓ Autostart updated for ${ORIENTATION} mode"
        restart_needed=0
    else
        log_info "✓ Openbox autostart unchanged"
    fi

    # Deploy touchscreen transformation script (for hot-plug support)
    if [ -f "${REPO_DIR}/scripts/apply-touchscreen-transform.sh" ]; then
        if ! diff -q "${REPO_DIR}/scripts/apply-touchscreen-transform.sh" "/opt/kiosk-apps/scripts/apply-touchscreen-transform.sh" >/dev/null 2>&1; then
            log_info "Updating touchscreen transformation script..."
            cp "${REPO_DIR}/scripts/apply-touchscreen-transform.sh" "/opt/kiosk-apps/scripts/apply-touchscreen-transform.sh"
            chmod +x "/opt/kiosk-apps/scripts/apply-touchscreen-transform.sh"
            log_info "✓ Touchscreen transformation script updated"
        else
            log_info "✓ Touchscreen transformation script unchanged"
        fi
    fi

    # Deploy udev rule for touchscreen hot-plug
    if [ -f "${REPO_DIR}/config/99-touchscreen-transform.rules" ]; then
        if ! diff -q "${REPO_DIR}/config/99-touchscreen-transform.rules" "/etc/udev/rules.d/99-touchscreen-transform.rules" >/dev/null 2>&1; then
            log_info "Updating udev rule for touchscreen hot-plug..."
            cp "${REPO_DIR}/config/99-touchscreen-transform.rules" "/etc/udev/rules.d/99-touchscreen-transform.rules"
            chmod 644 /etc/udev/rules.d/99-touchscreen-transform.rules

            # Reload udev rules
            udevadm control --reload-rules
            log_info "✓ Udev rule updated and reloaded"

            # Trigger rule for currently connected devices
            log_info "Applying transformation to currently connected touchscreens..."
            /opt/kiosk-apps/scripts/apply-touchscreen-transform.sh &
        else
            log_info "✓ Udev rule unchanged"
        fi
    fi

    return $restart_needed
}

# Main function
main() {
    log_section "Applying Kiosk Updates"

    # Verify running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Track if restart is needed
    local config_changed=1
    local scripts_changed=1
    local display_changed=1

    # Apply updates
    if apply_config_updates; then
        config_changed=0
    fi

    if apply_script_updates; then
        scripts_changed=0
    fi

    if apply_display_config; then
        display_changed=0
    fi

    apply_package_updates

    # Restart kiosk if configuration, scripts, or display changed
    if [ $config_changed -eq 0 ] || [ $scripts_changed -eq 0 ] || [ $display_changed -eq 0 ]; then
        log_section "Restarting Kiosk"
        log_info "Configuration, scripts, or display changed - restarting display manager..."

        # Give time for any pending operations
        sleep 2

        # Restart display manager (which will restart kiosk)
        # Use --no-block to avoid deadlock with boot-time dependencies
        systemctl --no-block restart lightdm
        log_info "✓ Display manager restart initiated"

        log_info "Kiosk should now be running with updated configuration"
    else
        log_info "✓ No restart needed"
    fi

    # Check if system reboot is required
    check_reboot_requirement

    log_section "Update Complete"
    log_info "Kiosk update process finished successfully"

    # Console completion message
    echo ""
    echo "========================================================"
    echo "  KIOSK-APPS UPDATE COMPLETE"
    echo "========================================================"
    if [ $config_changed -eq 0 ] || [ $scripts_changed -eq 0 ] || [ $display_changed -eq 0 ]; then
        echo "  Status: Configuration updated, kiosk restarted"
    else
        echo "  Status: No changes detected, kiosk running"
    fi
    echo "========================================================"
    echo ""
}

# Run main function
main "$@"
