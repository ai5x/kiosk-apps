#!/bin/bash
#
# Plymouth Progress Tracker for Kiosk-Apps
# Sends incremental progress updates to Plymouth during boot and update process
#

# Progress tracking variables
PROGRESS_FILE="/tmp/kiosk-apps-progress"
TOTAL_STEPS=100
CURRENT_STEP=0

# Initialize progress
init_progress() {
    echo "0" > "$PROGRESS_FILE"
    send_progress 0 "Initializing kiosk..."
}

# Send progress update to Plymouth
send_progress() {
    local percent=$1
    local message=$2

    if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
        plymouth system-update --progress="$percent" 2>/dev/null || true
        plymouth message --text="$message" 2>/dev/null || true
    fi

    echo "$percent" > "$PROGRESS_FILE"
}

# Update progress incrementally
update_progress() {
    local step=$1
    local total=$2
    local message=$3

    local percent=$((step * 100 / total))
    send_progress "$percent" "$message"
}

# Increment progress by amount
increment_progress() {
    local amount=$1
    local message=$2

    CURRENT_STEP=$((CURRENT_STEP + amount))
    if [ $CURRENT_STEP -gt $TOTAL_STEPS ]; then
        CURRENT_STEP=$TOTAL_STEPS
    fi

    send_progress "$CURRENT_STEP" "$message"
}

# Complete progress and quit Plymouth
complete_progress() {
    local message="${1:-Kiosk starting...}"

    send_progress 100 "$message"
    sleep 1

    # Quit Plymouth to allow kiosk GUI to take over
    if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
        plymouth quit 2>/dev/null || true
    fi
}

# Export functions for use in other scripts
export -f init_progress
export -f send_progress
export -f update_progress
export -f increment_progress
export -f complete_progress
