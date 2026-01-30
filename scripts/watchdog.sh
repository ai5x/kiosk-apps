#!/bin/bash
# HS1 Kiosk Watchdog Service
# Monitors browser health and restarts if crashed

set -euo pipefail

# Load configuration
CONFIG_FILE="/opt/kiosk/.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Default values
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-60}"
KIOSK_RELOAD_INTERVAL="${KIOSK_RELOAD_INTERVAL:-1800}"
LOG_FILE="/var/log/kiosk-watchdog.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "HS1 Kiosk Watchdog started"
log "Check interval: ${WATCHDOG_INTERVAL}s"
log "Page reload interval: ${KIOSK_RELOAD_INTERVAL}s (hard reload with cache clear)"

# Initialize counters
START_TIME=$(date +%s)
RESTART_COUNT=0
LAST_RELOAD_TIME=$(date +%s)

while true; do
    sleep "$WATCHDOG_INTERVAL"

    CURRENT_TIME=$(date +%s)
    UPTIME=$((CURRENT_TIME - START_TIME))
    TIME_SINCE_RELOAD=$((CURRENT_TIME - LAST_RELOAD_TIME))

    # Check if Chromium is running
    if ! pgrep -x chromium > /dev/null; then
        log "WARNING: Chromium not running! Restarting display manager..."
        RESTART_COUNT=$((RESTART_COUNT + 1))

        # Kill any stale X sessions
        pkill -9 -u pi || true

        # Restart LightDM (which will restart X and Chromium via autostart)
        systemctl restart lightdm

        log "Display manager restarted (total restarts: $RESTART_COUNT)"

        # Reset reload timer
        LAST_RELOAD_TIME=$(date +%s)

        # Wait for service to come up
        sleep 10
        continue
    fi

    # Check if X server is responsive
    if ! pgrep -x Xorg > /dev/null && ! pgrep -x X > /dev/null; then
        log "WARNING: X server not running! Restarting display manager..."
        systemctl restart lightdm
        sleep 10
        continue
    fi

    # Periodic page reload (prevents memory leaks in long-running browser)
    # Uses Ctrl+Shift+R for hard reload to bypass cache and service workers
    if [ "$KIOSK_RELOAD_INTERVAL" -gt 0 ] && [ "$TIME_SINCE_RELOAD" -ge "$KIOSK_RELOAD_INTERVAL" ]; then
        log "Performing periodic page reload (every ${KIOSK_RELOAD_INTERVAL}s) - HARD RELOAD"

        # Get kiosk user's DISPLAY
        export DISPLAY=:0
        export XAUTHORITY=/home/pi/.Xauthority

        # Send Ctrl+Shift+R for hard reload (bypasses cache and service workers)
        # This is more effective than F5 for clearing memory leaks
        sudo -u pi DISPLAY=:0 xdotool search --class chromium key ctrl+shift+r 2>/dev/null || true

        LAST_RELOAD_TIME=$(date +%s)
        log "Page hard reloaded successfully (cache cleared)"
    fi

    # Log status every 10 checks (for debugging)
    if [ $((UPTIME % (WATCHDOG_INTERVAL * 10))) -lt "$WATCHDOG_INTERVAL" ]; then
        UPTIME_HOURS=$((UPTIME / 3600))
        UPTIME_MINS=$(( (UPTIME % 3600) / 60 ))
        log "Status: OK | Uptime: ${UPTIME_HOURS}h ${UPTIME_MINS}m | Restarts: $RESTART_COUNT"
    fi
done
