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

# Plymouth message helper (shows status on boot screen)
plymouth_message() {
    if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
        plymouth message --text="$1" || true
    fi
}

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
        BACKUP_FILE=""
        if [ -f "$KIOSK_CONFIG" ]; then
            BACKUP_FILE="${KIOSK_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
            cp "$KIOSK_CONFIG" "$BACKUP_FILE"
            log_info "Backed up current config"
        fi

        # Copy new config
        cp "${REPO_DIR}/config/.env" "$KIOSK_CONFIG"
        chown root:root "$KIOSK_CONFIG"
        chmod 644 "$KIOSK_CONFIG"
        log_info "✓ Applied new configuration"

        # Log what changed
        if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
            log_info "Configuration changes:"
            diff -u "$BACKUP_FILE" "$KIOSK_CONFIG" | tail -n +3 | grep '^[-+]' | tee -a "$LOG_FILE" || true
        fi

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
            # Use --no-block to avoid deadlock during boot
            systemctl --no-block restart kiosk-watchdog.service
            log_info "✓ Restarted watchdog service (non-blocking)"
        fi
    fi

    if [ $restart_needed -eq 0 ]; then
        log_info "✓ Scripts unchanged"
    fi

    return $restart_needed
}

# Enable systemd services after package installation
enable_services_after_install() {
    if [ -f "${REPO_DIR}/config/enable-services.txt" ]; then
        # Read services to enable (skip comments and empty lines)
        SERVICES=$(grep -v '^#' "${REPO_DIR}/config/enable-services.txt" | grep -v '^$' | xargs)

        if [ -n "$SERVICES" ]; then
            log_info "Enabling services: $SERVICES"

            for service in $SERVICES; do
                # Check if service unit exists using systemctl directly
                if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
                    # Enable the service (idempotent - safe to run multiple times)
                    if systemctl enable "$service" >/dev/null 2>&1; then
                        log_info "✓ Enabled service: $service"
                    else
                        # Already enabled or failed - check which
                        if systemctl is-enabled "$service" >/dev/null 2>&1; then
                            log_info "✓ Service already enabled: $service"
                        else
                            log_warn "Failed to enable service: $service"
                        fi
                    fi

                    # Start the service if not already running
                    if systemctl is-active "$service" >/dev/null 2>&1; then
                        log_info "✓ Service already running: $service"
                    else
                        if systemctl start "$service" 2>&1 | tee -a "$LOG_FILE"; then
                            log_info "✓ Started service: $service"
                        else
                            log_warn "Failed to start service: $service"
                        fi
                    fi
                else
                    log_warn "Service unit not found: $service.service"
                fi
            done
        fi
    fi
}

# Apply package updates
apply_package_updates() {
    log_section "Package Updates"

    local packages_changed=0
    local critical_packages_installed=0

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
            APT_OUTPUT=$(DEBIAN_FRONTEND=noninteractive apt-get install -y $PACKAGES 2>&1 | tee -a "$LOG_FILE")
            if [ $? -eq 0 ]; then
                log_info "✓ Packages installed: $PACKAGES"
                packages_changed=1

                # Check if xinput was actually newly installed (not already present)
                # Look for pattern like "1 newly installed" or "2 newly installed" (not "0 newly installed")
                if echo "$APT_OUTPUT" | grep -E "[1-9][0-9]* newly installed" && echo "$PACKAGES" | grep -q "xinput"; then
                    log_info "Critical package 'xinput' was newly installed - touchscreen fix needed"
                    critical_packages_installed=1
                fi

                # Enable services if requested
                enable_services_after_install
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

    # Return 0 if critical packages were installed, 1 otherwise
    if [ $critical_packages_installed -eq 1 ]; then
        return 0  # Success: critical packages were installed
    else
        return 1  # Failure: no critical packages installed
    fi
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

    # Deploy display configuration script (for HDMI hot-plug support)
    if [ -f "${REPO_DIR}/scripts/apply-display-config.sh" ]; then
        if ! diff -q "${REPO_DIR}/scripts/apply-display-config.sh" "/opt/kiosk-apps/scripts/apply-display-config.sh" >/dev/null 2>&1; then
            log_info "Updating display configuration script..."
            cp "${REPO_DIR}/scripts/apply-display-config.sh" "/opt/kiosk-apps/scripts/apply-display-config.sh"
            chmod +x "/opt/kiosk-apps/scripts/apply-display-config.sh"
            log_info "✓ Display configuration script updated"
        else
            log_info "✓ Display configuration script unchanged"
        fi
    fi

    # Deploy udev rule for HDMI hot-plug
    if [ -f "${REPO_DIR}/config/99-hdmi-hotplug.rules" ]; then
        if ! diff -q "${REPO_DIR}/config/99-hdmi-hotplug.rules" "/etc/udev/rules.d/99-hdmi-hotplug.rules" >/dev/null 2>&1; then
            log_info "Updating udev rule for HDMI hot-plug..."
            cp "${REPO_DIR}/config/99-hdmi-hotplug.rules" "/etc/udev/rules.d/99-hdmi-hotplug.rules"
            chmod 644 /etc/udev/rules.d/99-hdmi-hotplug.rules

            # Reload udev rules
            udevadm control --reload-rules
            log_info "✓ HDMI hotplug udev rule updated and reloaded"

            # Trigger rule for currently connected displays
            log_info "Applying display configuration to currently connected HDMI..."
            /opt/kiosk-apps/scripts/apply-display-config.sh &
        else
            log_info "✓ HDMI hotplug udev rule unchanged"
        fi
    fi

    # Deploy udev rule for global USB power management disable
    if [ -f "${REPO_DIR}/config/50-usb-power-disable.rules" ]; then
        if ! diff -q "${REPO_DIR}/config/50-usb-power-disable.rules" "/etc/udev/rules.d/50-usb-power-disable.rules" >/dev/null 2>&1; then
            log_info "Updating udev rule for USB power management..."
            cp "${REPO_DIR}/config/50-usb-power-disable.rules" "/etc/udev/rules.d/50-usb-power-disable.rules"
            chmod 644 /etc/udev/rules.d/50-usb-power-disable.rules

            # Remove old touchscreen-specific rule if present
            if [ -f "/etc/udev/rules.d/50-touchscreen-power.rules" ]; then
                rm -f /etc/udev/rules.d/50-touchscreen-power.rules
                log_info "Removed old touchscreen-specific rule"
            fi

            # Reload udev rules and trigger for currently connected devices
            udevadm control --reload-rules
            udevadm trigger --subsystem-match=usb
            log_info "✓ USB power management disabled globally"
        else
            log_info "✓ USB power management rule unchanged"
        fi
    fi

    return $restart_needed
}

# Deploy PCIe power management udev rule
apply_pcie_power_rule() {
    if [ -f "${REPO_DIR}/config/99-disable-power-management.rules" ]; then
        if ! diff -q "${REPO_DIR}/config/99-disable-power-management.rules" "/etc/udev/rules.d/99-disable-power-management.rules" >/dev/null 2>&1; then
            log_info "Deploying PCIe/PCI power management udev rule..."
            cp "${REPO_DIR}/config/99-disable-power-management.rules" "/etc/udev/rules.d/99-disable-power-management.rules"
            chmod 644 /etc/udev/rules.d/99-disable-power-management.rules

            # Reload and trigger
            udevadm control --reload-rules
            udevadm trigger --subsystem-match=pci

            log_info "✓ PCIe power management udev rule deployed"
        else
            log_info "✓ PCIe power management rule unchanged"
        fi
    fi
}

# Deploy CPU performance mode systemd service
apply_cpu_performance_service() {
    local service_changed=false

    if [ -f "${REPO_DIR}/systemd/disable-cpu-powersave.service" ]; then
        if ! diff -q "${REPO_DIR}/systemd/disable-cpu-powersave.service" "/etc/systemd/system/disable-cpu-powersave.service" >/dev/null 2>&1; then
            log_info "Installing CPU performance mode service..."
            cp "${REPO_DIR}/systemd/disable-cpu-powersave.service" "/etc/systemd/system/disable-cpu-powersave.service"
            chmod 644 /etc/systemd/system/disable-cpu-powersave.service

            # Reload systemd and enable service
            systemctl daemon-reload
            systemctl enable disable-cpu-powersave.service
            systemctl start disable-cpu-powersave.service

            log_info "✓ CPU performance mode service installed and started"
            service_changed=true
        else
            # Ensure service is enabled even if file hasn't changed
            if ! systemctl is-enabled disable-cpu-powersave.service >/dev/null 2>&1; then
                systemctl enable disable-cpu-powersave.service
                systemctl start disable-cpu-powersave.service
                log_info "✓ CPU performance mode service enabled"
                service_changed=true
            else
                log_info "✓ CPU performance mode service unchanged"
            fi
        fi
    fi

    if [ "$service_changed" = true ]; then
        # Verify CPUs are in performance mode
        PERF_COUNT=$(grep -c "performance" /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || echo 0)
        log_info "  $PERF_COUNT CPU cores set to performance mode"
    fi
}

# Deploy Xbox controller (xpad) configuration
apply_xpad_config() {
    # Deploy modprobe config for xpad driver (Xbox controllers)
    if [ -f "${REPO_DIR}/config/xpad.conf" ]; then
        if ! diff -q "${REPO_DIR}/config/xpad.conf" "/etc/modprobe.d/xpad.conf" >/dev/null 2>&1; then
            log_info "Updating xpad (Xbox controller) configuration..."
            cp "${REPO_DIR}/config/xpad.conf" "/etc/modprobe.d/xpad.conf"
            chmod 644 /etc/modprobe.d/xpad.conf

            # Apply to currently loaded xpad module if present
            if lsmod | grep -q "^xpad"; then
                log_info "Applying auto_poweroff=0 to loaded xpad module..."
                echo N > /sys/module/xpad/parameters/auto_poweroff 2>/dev/null || true
            fi

            log_info "✓ Xbox controller auto-poweroff disabled"
        else
            log_info "✓ xpad configuration unchanged"
        fi
    fi
}

# Deploy Plymouth boot progress theme
apply_plymouth_theme() {
    if [ -f "${REPO_DIR}/plymouth/hs1-kiosk-theme/hs1-kiosk-theme.script" ]; then
        THEME_DIR="/usr/share/plymouth/themes/hs1-kiosk-theme"

        # Ensure theme directory exists
        mkdir -p "$THEME_DIR"

        # Deploy theme script
        if ! diff -q "${REPO_DIR}/plymouth/hs1-kiosk-theme/hs1-kiosk-theme.script" "${THEME_DIR}/hs1-kiosk-theme.script" >/dev/null 2>&1; then
            log_info "Updating Plymouth boot progress theme..."
            cp "${REPO_DIR}/plymouth/hs1-kiosk-theme/hs1-kiosk-theme.script" "${THEME_DIR}/hs1-kiosk-theme.script"
            chmod 644 "${THEME_DIR}/hs1-kiosk-theme.script"
            log_info "✓ Plymouth theme updated"

            # Note: logo.png is NOT deployed - it's portrait-specific and already on kiosk
            if [ ! -f "${THEME_DIR}/logo.png" ]; then
                log_warn "Plymouth logo.png missing at ${THEME_DIR}/logo.png"
                log_warn "This is expected for first-time setup - logo must be deployed manually"
            fi
        else
            log_info "✓ Plymouth theme unchanged"
        fi
    fi
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
    local critical_packages_installed=1

    # Apply updates
    if apply_config_updates; then
        config_changed=0
    fi

    if apply_script_updates; then
        scripts_changed=0
    fi

    # Stage 2 complete: Configuration loaded
    plymouth_message "STAGE:2"

    if apply_package_updates; then
        critical_packages_installed=0
    fi

    # Stage 3 complete: Packages installed
    plymouth_message "STAGE:3"

    if apply_display_config; then
        display_changed=0
    fi

    # Stage 4 complete: Display configured
    plymouth_message "STAGE:4"

    # Apply Xbox controller configuration
    apply_xpad_config

    # Apply Plymouth boot progress theme
    apply_plymouth_theme

    # Apply permanent power management configurations
    log_section "Applying Power Management Configuration"
    apply_pcie_power_rule
    apply_cpu_performance_service

    # Disable all power management features for industrial reliability (runtime)
    log_section "Disabling Power Management (Runtime)"
    if [ -x "${REPO_DIR}/scripts/disable-power-management.sh" ]; then
        "${REPO_DIR}/scripts/disable-power-management.sh"
        log_info "✓ Power management features disabled"
    else
        log_warn "Power management script not found or not executable"
    fi

    # If critical packages (xinput) or display config changed, apply transformation immediately
    if [ $critical_packages_installed -eq 0 ] || [ $display_changed -eq 0 ]; then
        log_section "Applying Touchscreen Transformation"
        log_info "Critical changes detected - applying touchscreen transformation to current session..."

        # Wait for X server and newly installed packages to be ready
        sleep 3

        # Run transformation script synchronously (not in background)
        if [ -x "/opt/kiosk-apps/scripts/apply-touchscreen-transform.sh" ]; then
            log_info "Running transformation script..."
            /opt/kiosk-apps/scripts/apply-touchscreen-transform.sh
            log_info "✓ Transformation script completed"
        else
            log_warn "Transformation script not found or not executable"
        fi
    fi

    # Restart kiosk if configuration, scripts, display, or critical packages changed
    if [ $config_changed -eq 0 ] || [ $scripts_changed -eq 0 ] || [ $display_changed -eq 0 ] || [ $critical_packages_installed -eq 0 ]; then
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

    # Stage 5 complete: System ready
    plymouth_message "STAGE:5"

    log_section "Update Complete"
    log_info "Kiosk update process finished successfully"

    # Get current version for completion message
    CURRENT_VERSION="unknown"
    if [ -d "${REPO_DIR}/.git" ]; then
        cd "${REPO_DIR}"
        CURRENT_VERSION=$(git describe --tags --always 2>/dev/null || echo "unknown")
    fi

    # Console completion message
    echo ""
    echo "========================================================"
    echo "  KIOSK-APPS UPDATE COMPLETE"
    echo "========================================================"
    echo "  Version: $CURRENT_VERSION"
    if [ $config_changed -eq 0 ] || [ $scripts_changed -eq 0 ] || [ $display_changed -eq 0 ]; then
        echo "  Status: Configuration updated, kiosk restarted"
    else
        echo "  Status: No changes detected, kiosk running"
    fi
    echo "========================================================"
    echo ""

    # Plymouth will exit automatically after stage 5
    # Chromium kiosk will indicate system is running
}

# Run main function
main "$@"
