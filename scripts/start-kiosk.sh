#!/bin/bash
# HS1 Kiosk - Chromium Browser Launcher
# Starts Chromium in full-screen kiosk mode

set -euo pipefail

# Load configuration
CONFIG_FILE="/opt/kiosk/.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Append kiosk=hs1 parameter to URL for soft keyboard detection
if [[ "$KIOSK_URL" == *"?"* ]]; then
    # URL already has query params
    KIOSK_URL="${KIOSK_URL}&kiosk=hs1"
else
    # No query params yet
    KIOSK_URL="${KIOSK_URL}?kiosk=hs1"
fi

# Log startup
LOG_FILE="/var/log/kiosk.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting HS1 Kiosk..." | tee -a "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Target URL: $KIOSK_URL" | tee -a "$LOG_FILE"

# Wait for network to be available
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for network..." | tee -a "$LOG_FILE"
MAX_WAIT=5
COUNT=0
while ! ping -c 1 -W 1 192.168.1.30 >/dev/null 2>&1; do
    sleep 1
    COUNT=$((COUNT + 1))
    if [ $COUNT -ge $MAX_WAIT ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Network timeout, proceeding anyway..." | tee -a "$LOG_FILE"
        break
    fi
done

if [ $COUNT -lt $MAX_WAIT ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Network available" | tee -a "$LOG_FILE"
fi

# Clean up any previous Chromium sessions
rm -rf /home/pi/.config/chromium/Singleton*
rm -rf /home/pi/.config/chromium/SingletonLock

# Create Chromium preferences to disable restore prompts
mkdir -p /home/pi/.config/chromium/Default
cat > /home/pi/.config/chromium/Default/Preferences <<EOF
{
   "profile": {
      "exit_type": "Normal",
      "exited_cleanly": true
   },
   "browser": {
      "check_default_browser": false,
      "show_home_button": false
   },
   "bookmark_bar": {
      "show_on_all_tabs": false
   },
   "distribution": {
      "skip_first_run_ui": true,
      "show_welcome_page": false,
      "import_history": false,
      "import_bookmarks": false,
      "import_search_engine": false,
      "import_saved_passwords": false
   }
}
EOF

# Set Chromium as default browser
export BROWSER=chromium

# Disable screen blanking and power management
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Start Chromium in kiosk mode
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching Chromium..." | tee -a "$LOG_FILE"

# Chromium flags for kiosk mode
# --kiosk: Full-screen kiosk mode
# --noerrdialogs: Disable error dialogs
# --disable-infobars: No info bars
# --no-first-run: Skip first run experience
# --check-for-update-interval: Disable update checks (0 = never)
# --disable-features: Disable translate, save password prompts
# --disable-session-crashed-bubble: Don't show crash bubble
# --disable-restore-session-state: Don't restore previous session
# --disable-component-update: Disable component updates
# --autoplay-policy: Allow autoplay (for videos if needed)
# --start-fullscreen: Start in fullscreen
# --window-position: Position at 0,0
# --disk-cache-size: Limit cache size
# --js-flags: JavaScript engine flags (max-old-space-size = 2800MB heap limit)

chromium \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --check-for-update-interval=31536000 \
    --disable-features=TranslateUI,PasswordManager \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --disable-component-update \
    --autoplay-policy=no-user-gesture-required \
    --start-fullscreen \
    --window-position=0,0 \
    --window-size=1080,1920 \
    --disk-cache-size=104857600 \
    --disable-dev-shm-usage \
    --disable-software-rasterizer \
    --disable-gpu-driver-bug-workarounds \
    --enable-features=OverlayScrollbar \
    --force-device-scale-factor=1 \
    --ignore-certificate-errors \
    --allow-insecure-localhost \
    --js-flags="--max-old-space-size=2800" \
    "$KIOSK_URL" \
    >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Chromium exited" | tee -a "$LOG_FILE"
