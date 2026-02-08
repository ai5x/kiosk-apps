#!/bin/bash
#
# Apply display configuration based on HDMI connection state
# This script is triggered by udev when HDMI is connected/disconnected
# and can also be run manually to reapply display settings
#

set -euo pipefail

# Configuration
KIOSK_CONFIG="/opt/kiosk/.env"
LOG_FILE="/tmp/display-config.log"

# Set up X display access
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/home/pi/.Xauthority}"

# When run as root (via udev or sudo), use pi user's X authority
if [ "$EUID" -eq 0 ] && [ -f "/home/pi/.Xauthority" ]; then
    export XAUTHORITY="/home/pi/.Xauthority"
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Exit if config doesn't exist
if [ ! -f "$KIOSK_CONFIG" ]; then
    log "Config file not found: $KIOSK_CONFIG"
    exit 0
fi

# Read orientation from config
source "$KIOSK_CONFIG"
ORIENTATION="${DISPLAY_ORIENTATION:-landscape}"

log "Applying display configuration for orientation: $ORIENTATION"

# Wait for X server to fully detect the display
sleep 2

# Detect HDMI output name (could be HDMI-1, HDMI-2, HDMI-A-1, etc.)
HDMI_OUTPUT=$(xrandr 2>/dev/null | grep -E "^(HDMI|HDMI-A|HDMI-1|HDMI-2)" | grep " connected" | awk '{print $1}' | head -1 || true)

if [ -z "$HDMI_OUTPUT" ]; then
    log "No HDMI display detected"
    exit 0
fi

log "Detected HDMI output: $HDMI_OUTPUT"

# Apply rotation based on orientation
case "$ORIENTATION" in
    portrait)
        log "Setting display to portrait mode (90° clockwise)"
        if xrandr --output "$HDMI_OUTPUT" --rotate right 2>&1 | tee -a "$LOG_FILE"; then
            log "✓ Display rotated to portrait"
        else
            log "✗ Failed to rotate display"
            exit 1
        fi
        ;;
    portrait-inverted)
        log "Setting display to portrait-inverted mode (270° clockwise)"
        if xrandr --output "$HDMI_OUTPUT" --rotate left 2>&1 | tee -a "$LOG_FILE"; then
            log "✓ Display rotated to portrait-inverted"
        else
            log "✗ Failed to rotate display"
            exit 1
        fi
        ;;
    landscape|*)
        log "Setting display to landscape mode (no rotation)"
        if xrandr --output "$HDMI_OUTPUT" --rotate normal 2>&1 | tee -a "$LOG_FILE"; then
            log "✓ Display set to landscape"
        else
            log "✗ Failed to set display orientation"
            exit 1
        fi
        ;;
esac

# Disable screen blanking and power management
log "Disabling screen blanking and power management"
xset s off 2>&1 | tee -a "$LOG_FILE" || true
xset -dpms 2>&1 | tee -a "$LOG_FILE" || true
xset s noblank 2>&1 | tee -a "$LOG_FILE" || true

log "Display configuration complete"
