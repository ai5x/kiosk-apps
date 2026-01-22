#!/bin/bash
#
# Apply touchscreen coordinate transformation based on display orientation
# This script is triggered by udev when input devices are added/changed
# and can also be run manually to reapply transformation
#

set -euo pipefail

# Configuration
KIOSK_CONFIG="/opt/kiosk/.env"
LOG_FILE="/tmp/touchscreen-transform.log"
DISPLAY="${DISPLAY:-:0}"

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

log "Applying touchscreen transformation for orientation: $ORIENTATION"

# Determine transformation matrix based on orientation
case "$ORIENTATION" in
    portrait)
        # 90° clockwise rotation
        MATRIX="0 1 0 -1 0 1 0 0 1"
        log "Matrix: Portrait (90° clockwise)"
        ;;
    portrait-inverted)
        # 270° clockwise (90° counter-clockwise)
        MATRIX="0 -1 1 1 0 0 0 0 1"
        log "Matrix: Portrait inverted (270° clockwise)"
        ;;
    landscape|*)
        # No transformation (identity matrix)
        MATRIX="1 0 0 0 1 0 0 0 1"
        log "Matrix: Landscape (no rotation)"
        ;;
esac

# Wait a moment for X server to fully register new devices
sleep 1

# Find all touchscreen devices and apply transformation
TOUCH_DEVICES=$(DISPLAY=$DISPLAY xinput list 2>/dev/null | grep -i "touch" | grep -o 'id=[0-9]*' | cut -d= -f2 || true)

if [ -z "$TOUCH_DEVICES" ]; then
    log "No touchscreen devices found"
    exit 0
fi

for device in $TOUCH_DEVICES; do
    log "Applying transformation to device $device"
    if DISPLAY=$DISPLAY xinput set-prop "$device" 'Coordinate Transformation Matrix' $MATRIX 2>&1 | tee -a "$LOG_FILE"; then
        log "✓ Transformation applied to device $device"
    else
        log "✗ Failed to apply transformation to device $device"
    fi
done

log "Touchscreen transformation complete"
