# Kiosk-Apps OTA Configuration System

## Overview

Kiosk-apps provides Over-The-Air (OTA) configuration management for deployed HS1 kiosks. This allows remote updates to all kiosk settings without SD card reflashing.

**Repository:** https://github.com/ai5x/kiosk-apps (public)

## Key Principle

**Always prefer kiosk-apps updates over hs1-kiosk image changes.**

- ✅ Configuration changes → Edit kiosk-apps, git push
- ✅ Script updates → Edit kiosk-apps, git push
- ✅ Screen rotation → Edit kiosk-apps, git push
- ❌ Image changes → Only for base OS/provisioning updates (rare)

## Architecture

```
Every Boot:
  ├─ kiosk-apps-sync.service runs
  ├─ Auto-clone repo if missing (recovery)
  ├─ git fetch + pull latest changes
  ├─ Apply configuration updates
  ├─ Apply display rotation config
  ├─ Run package updates if requested
  └─ Restart kiosk if needed
```

## Version Management and Releases

**When to create a release:**
- After significant feature additions (new scripts, major configuration changes)
- After bug fixes that affect kiosk stability or functionality
- Before deploying to production kiosks
- When you want to track a specific deployment version

**Release workflow:**
```bash
# 1. Make your changes and test on a single kiosk first
git add <files>
git commit -m "Descriptive commit message"

# 2. Create a git tag for the release
# Use semantic versioning: vMAJOR.MINOR.PATCH
# - MAJOR: Breaking changes (rare for config-only project)
# - MINOR: New features, new scripts, significant updates
# - PATCH: Bug fixes, small config changes
git tag -a v1.2.3 -m "Release v1.2.3: Brief description of changes"

# 3. Push commits and tags
git push && git push --tags

# 4. Create GitHub release (optional but recommended)
gh release create v1.2.3 --title "v1.2.3: Release title" --notes "
## Changes
- Feature/fix description
- Another change
- Bug fixes

## Testing
Tested on kiosk at 192.168.1.122
"
```

**Default version increment:**
- Configuration changes, script updates: **PATCH** (v1.0.0 → v1.0.1)
- New features, new scripts: **MINOR** (v1.0.1 → v1.1.0)
- Breaking changes: **MAJOR** (v1.1.0 → v2.0.0)

**Quick release command:**
```bash
# After committing changes
git tag v1.0.1 && git push --tags
```

**View current version:**
```bash
git describe --tags --abbrev=0  # Latest tag
git log --oneline -1            # Latest commit
```

## Configuration Files

### Primary Config: `config/.env`

```bash
# Target URL - the web application to display
KIOSK_URL=http://192.168.1.30/

# Page reload interval (seconds, 0 to disable)
KIOSK_RELOAD_INTERVAL=3600

# Watchdog check interval (seconds)
WATCHDOG_INTERVAL=60

# Display orientation: landscape, portrait, portrait-inverted
DISPLAY_ORIENTATION=portrait

# Enable touchscreen coordinate transformation
ENABLE_TOUCHSCREEN_TRANSFORM=true
```

### Display Rotation Configs

**Files:**
- `config/openbox-autostart-landscape` - No rotation (1920x1080)
- `config/openbox-autostart-portrait` - 90° clockwise (1080x1920)
- `config/openbox-autostart-portrait-inverted` - 270° clockwise (1080x1920)

**Deployed to:** `/home/pi/.config/openbox/autostart` based on `DISPLAY_ORIENTATION`

**X Server Config:**
- `config/xorg-modesetting.conf` → `/etc/X11/xorg.conf.d/99-v3d.conf`

## Common Operations

### Change Screen Rotation

```bash
# Edit config/.env
DISPLAY_ORIENTATION=portrait  # or landscape, portrait-inverted

# Commit and push
git add config/.env
git commit -m "Change orientation to portrait"
git push

# All kiosks will apply change on next boot
```

### Change Kiosk URL

```bash
# Edit config/.env
KIOSK_URL=http://192.168.1.50/

git add config/.env
git commit -m "Update kiosk URL to new frontend"
git push
```

### Update Watchdog Interval

```bash
# Edit config/.env
WATCHDOG_INTERVAL=30  # Check every 30 seconds

git add config/.env
git commit -m "Increase watchdog frequency"
git push
```

### Deploy Script Updates

```bash
# Edit scripts/start-kiosk.sh or scripts/watchdog.sh
# Make your changes

git add scripts/
git commit -m "Update start-kiosk.sh to add new Chromium flags"
git push

# On next boot, apply-updates.sh will deploy new scripts to /opt/kiosk/
```

### Install Missing Packages

```bash
# Add packages to config/install-packages.txt (permanent)
echo "# Required packages" > config/install-packages.txt
echo "xinput" >> config/install-packages.txt
echo "some-other-package" >> config/install-packages.txt

git add config/install-packages.txt
git commit -m "Add required packages for kiosks"
git push

# On next boot, apt-get install will install these packages
# These packages are checked on every boot (persistent file)
```

### Enable Services After Installation

```bash
# Add services to config/enable-services.txt (permanent)
# Services will be enabled and started after package installation
echo "# Services to enable" > config/enable-services.txt
echo "prometheus-node-exporter" >> config/enable-services.txt
echo "some-other-service" >> config/enable-services.txt

git add config/enable-services.txt
git commit -m "Enable monitoring services on kiosks"
git push

# On next boot, services will be enabled and started after packages install
# Useful for packages that don't auto-enable their services
```

### Trigger Package Updates/Upgrades

```bash
# Create update-packages.txt to trigger full apt upgrade (one-time)
touch config/update-packages.txt

git add config/update-packages.txt
git commit -m "Trigger package upgrade on all kiosks"
git push

# On next boot, apt-get upgrade will run
# File is deleted after successful upgrade
```

**Note:** `install-packages.txt` is persistent and checks/installs packages on every boot. `update-packages.txt` is a one-time trigger that gets deleted after running.

## Auto-Recovery System

The kiosk-apps system includes automatic recovery mechanisms:

### Auto-Clone on Boot

If `/opt/kiosk-apps` is missing or corrupted:
```
1. kiosk-apps-sync.service detects missing repo
2. Attempts git clone from GitHub
3. Applies configuration
4. Continues with fallback config if clone fails
```

### Network Failure Handling

```bash
# sync-and-update.sh behavior:
- No network → Continue with current version
- Git fetch fails → Continue with current version
- Git pull fails → Rollback to previous commit
- Apply-updates fails → Log error, continue operation
```

### GitHub Token Support

For private repo or rate limiting:

```bash
# On kiosk, create token file:
sudo mkdir -p /etc/kiosk-apps
echo "GITHUB_TOKEN=ghp_yourtoken" | sudo tee /etc/kiosk-apps/github-token
sudo chmod 600 /etc/kiosk-apps/github-token

# Or during first boot, add to /boot/firmware/kiosk-config.txt:
GITHUB_TOKEN=ghp_yourtoken
```

## Manual Installation (Existing Kiosks)

To install kiosk-apps on a kiosk that doesn't have it:

```bash
# SSH to kiosk
ssh pi@192.168.1.122

# Run installer script
cd /opt/kiosk-apps  # If already cloned
sudo bash scripts/install-sync-service.sh

# Or clone first, then install
sudo git clone https://github.com/ai5x/kiosk-apps.git /opt/kiosk-apps
cd /opt/kiosk-apps
sudo bash scripts/install-sync-service.sh
```

## Deployment Flow

```
Developer:
  ├─ Edit config/.env or scripts/
  ├─ git commit -m "Update config"
  ├─ git push

Kiosks (on next boot):
  ├─ kiosk-apps-sync.service runs
  ├─ git pull latest changes
  ├─ apply-updates.sh runs
  ├─ Compare configs, deploy if changed
  ├─ Restart lightdm if needed
  └─ Kiosk now running with new config
```

## Touchscreen Calibration

Touchscreen transformation matrices are applied automatically based on rotation:

**Portrait (90° clockwise):**
```bash
xinput set-prop <device> 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1
```

**Portrait Inverted (270° clockwise):**
```bash
xinput set-prop <device> 'Coordinate Transformation Matrix' 0 -1 1 1 0 0 0 0 1
```

**Landscape:**
No transformation (identity matrix)

## Logging and Debugging

**Boot screen progress (Plymouth):**
During boot, kiosk-apps displays update progress on the Plymouth splash screen:
- Current commit version being deployed
- Git fetch/update status
- Configuration, package, and display update progress
- Shows system is working and not hung
- Messages appear below the ai5x logo at default Plymouth message location

**Service logs:**
```bash
# View sync service status
systemctl status kiosk-apps-sync.service

# View sync logs
tail -f /var/log/kiosk-apps-sync.log

# View systemd journal
journalctl -u kiosk-apps-sync.service -f
```

**Openbox autostart logs:**
```bash
# View rotation/touchscreen setup logs
cat /tmp/openbox-autostart.log
```

**Apply-updates logs:**
```bash
# Included in /var/log/kiosk-apps-sync.log
```

## Testing Changes

**Test on single kiosk first:**
```bash
# SSH to test kiosk
ssh pi@192.168.1.122

# Manually trigger sync
sudo systemctl start kiosk-apps-sync.service

# Check logs
tail -f /var/log/kiosk-apps-sync.log

# Verify configuration applied
cat /opt/kiosk/.env
cat /home/pi/.config/openbox/autostart
```

**Rollback if needed:**
```bash
# On your machine
git revert HEAD
git push

# Kiosks will auto-revert on next boot
```

## Best Practices

1. **Test changes on one kiosk first** before deploying to all
2. **Use descriptive commit messages** - they appear in kiosk logs
3. **Keep .env comments up to date** - they're the primary documentation
4. **Avoid breaking changes** - ensure backward compatibility
5. **Monitor first few deployments** - check logs after pushing changes
6. **Use git tags** for major configuration releases
7. **Document config changes** in commit messages

## Troubleshooting

**Kiosk not updating:**
```bash
# Check service is enabled
systemctl is-enabled kiosk-apps-sync.service

# Check service status
systemctl status kiosk-apps-sync.service

# Check network connectivity
ping -c 3 github.com

# Manually trigger update
sudo systemctl start kiosk-apps-sync.service
```

**Rotation not applying:**
```bash
# Check current config
cat /opt/kiosk-apps/config/.env | grep DISPLAY_ORIENTATION

# Check deployed autostart
cat /home/pi/.config/openbox/autostart

# Check autostart log
cat /tmp/openbox-autostart.log

# Manually restart display manager
sudo systemctl restart lightdm
```

**Touchscreen not calibrated:**
```bash
# Check if xinput is installed (required for touchscreen transformation)
which xinput
# If missing, add to config/install-packages.txt and reboot

# Check if xinput found devices
DISPLAY=:0 xinput list | grep -i touch

# Check transformation matrix
DISPLAY=:0 xinput list-props <device-id> | grep "Coordinate Transformation"

# Check autostart log for errors
cat /tmp/openbox-autostart.log

# Expected matrix for portrait (90° clockwise):
# 0.000000, 1.000000, 0.000000, -1.000000, 0.000000, 1.000000, 0.000000, 0.000000, 1.000000

# If xinput command not found during boot:
# Add xinput to config/install-packages.txt
echo "xinput" >> config/install-packages.txt
git add config/install-packages.txt
git commit -m "Add xinput package for touchscreen support"
git push
# Reboot kiosk to install
```

## Repository Structure

```
kiosk-apps/
├── config/
│   ├── .env                              # Main configuration
│   ├── install-packages.txt              # Packages to install (persistent)
│   ├── enable-services.txt               # Services to enable after install (persistent)
│   ├── update-packages.txt               # Trigger for apt upgrade (one-time, optional)
│   ├── xorg-modesetting.conf            # X server config
│   ├── openbox-autostart-landscape      # Landscape rotation
│   ├── openbox-autostart-portrait       # Portrait rotation (90°)
│   ├── openbox-autostart-portrait-inverted  # Portrait inverted (270°)
│   └── 99-touchscreen-transform.rules   # Udev rule for touchscreen hot-plug
├── scripts/
│   ├── sync-and-update.sh               # Main sync script (runs on boot)
│   ├── apply-updates.sh                 # Apply configuration changes
│   ├── apply-touchscreen-transform.sh   # Apply touchscreen transformation
│   └── install-sync-service.sh          # Manual installation script
├── systemd/
│   └── kiosk-apps-sync.service          # Systemd service definition
├── CLAUDE.md                            # Development documentation
└── README.md                            # User documentation
```

## Common Issues & Recent Fixes

### Issue: Touchscreen not responding in portrait mode
**Symptoms:** Display rotates correctly but touch input is misaligned
**Cause:** xinput package missing - transformation commands fail silently
**Fix:** Added xinput to config/install-packages.txt
**Commit:** 7f738cc (2026-01-22)

### Issue: Kiosk hangs at Plymouth screen on boot
**Symptoms:** Boot process stops at splash screen, no login prompt
**Cause:** Circular dependency - kiosk-apps-sync.service has Before=lightdm but calls systemctl restart lightdm (blocking)
**Fix:** Added --no-block flag to systemctl restart lightdm
**Commit:** 0eb7190 (2026-01-22)

### Issue: Git fetch fails with "couldn't find remote ref main"
**Symptoms:** Sync service runs but no updates applied, logs show fatal git error
**Cause:** Repository uses 'master' branch but scripts referenced 'main'
**Fix:** Changed all git fetch/pull commands from main to master
**Commit:** 0eb7190 (2026-01-22)

### Issue: Can't see provisioning progress on first boot
**Symptoms:** Console only shows cloud-init, no indication of kiosk setup progress
**Cause:** systemd services output to journal only, not console
**Fix:** Changed StandardOutput=journal+console in both services
**Commit:** 58b10c3 (2026-01-22)

### Issue: Kiosk-apps clone fails during provisioning (private repo)
**Symptoms:** First boot provisioning completes but OTA updates don't work
**Cause:** Repository was private without token, initial clone failed
**Solution:** Made repository public OR add token to /etc/kiosk-apps/github-token
**Auto-recovery:** Service auto-clones repo on next boot if missing
**Commit:** d31a152 (2026-01-22)

### Issue: OTA updates don't fix incorrect touchscreen on existing kiosks
**Symptoms:** Kiosks with bad touchscreen state don't get fixed by OTA updates
**Cause:** When xinput is installed via OTA, openbox autostart doesn't re-run, so transformation commands that failed initially never get applied to current session
**Fix:** Added automatic touchscreen transformation when critical packages (xinput) are newly installed
- Detect fresh xinput installation (not already present)
- Apply transformation synchronously after installation
- Trigger lightdm restart to ensure clean state
**Commits:** ed193e9, 235336f (2026-01-23)

### Issue: Touchscreen not working after OTA update (udev timeout)
**Symptoms:** Touchscreen completely unresponsive, software configuration appears correct
**Cause:** Udev rule was running transformation script synchronously, causing 3-minute timeout and script termination
**Root cause:** Script's `sleep 2` and X server communication blocked udev worker, which killed the process after timeout
**Fix:** Use `systemd-run --no-block` to execute transformation script asynchronously
- Udev no longer waits for script completion
- Hot-plug events complete successfully
- Touchscreen transformation applies in background
**Commit:** c4cf182 (2026-01-23)
**Version:** v1.1.20

### Issue: HDMI display not working after hotplug
**Symptoms:** If kiosk boots without HDMI connected, display won't work when cable is later plugged in
**Cause:** X11 doesn't detect display at boot, xrandr configuration not reapplied on hotplug
**Fix:** Implemented HDMI hotplug detection system
- Created `scripts/apply-display-config.sh` to dynamically detect and configure HDMI output
- Added udev rule `config/99-hdmi-hotplug.rules` to trigger on DRM device changes
- Updated all openbox autostart scripts to use dynamic HDMI detection instead of hardcoded HDMI-1
- Script automatically detects HDMI output name (HDMI-1, HDMI-A-1, etc.) and applies rotation
**Benefits:**
- Display works even if cable connected after boot
- Handles different HDMI output naming schemes
- Automatic reconfiguration when display reconnected
**Commit:** TBD (2026-02-08)
**Version:** v1.2.1

### Issue: Touchscreen detection wasting boot time on non-touch kiosks
**Symptoms:** HDMI-only kiosks (without touchscreen hardware) waste 10+ seconds at boot attempting to detect non-existent touchscreen devices, creating confusing "No touch devices found, attempt 1/10" log messages
**Root Cause:**
- `ENABLE_TOUCHSCREEN_TRANSFORM=true` was hardcoded globally in config
- Openbox autostart scripts always attempted touchscreen detection (10 attempts)
- Using `source` command to load config failed silently in openbox environment - variables weren't being set
**Fix:**
1. Made openbox autostart scripts respect `ENABLE_TOUCHSCREEN_TRANSFORM` config flag
2. Reduced detection attempts from 10 to 3 (saves ~7 seconds)
3. **Critical: Changed `source` to `.` (dot) notation** - `source` doesn't work reliably in openbox environment
4. Added config documentation explaining the option for HDMI-only displays
5. Improved error handling (`2>/dev/null`, `|| true`)
**Benefits:**
- Faster boot times on non-touch kiosks (~10 seconds saved)
- Cleaner logs without repeated "device not found" messages
- Easy per-kiosk configuration via ENABLE_TOUCHSCREEN_TRANSFORM=false
- No impact on kiosks that actually have touchscreens
**Testing:** Kiosk at 192.168.1.42 (HDMI-only) - touchscreen detection now skipped, boot time improved
**Commits:** 0124ed5, 565719c (2026-02-08)
**Version:** v1.2.3

### Issue: False positive xinput installation detection
**Symptoms:** Kiosk unnecessarily restarts lightdm on every boot even when xinput already installed
**Cause:** Detection logic matched "0 newly installed" as a trigger condition
**Fix:** Use regex to only match when 1+ packages actually installed (not "0 newly installed")
**Commit:** 214603c (2026-01-23)
**Version:** v1.1.19

### Enhancement: Version display improvements
**Implementation:** Multiple improvements to show version tags prominently
- v1.1.18: Version included in all Plymouth message prefixes (e.g., "Kiosk-Apps v1.1.18: Status")
- v1.1.17: Display current version immediately on startup
- v1.1.16: Fetch git tags during sync to enable version tag display
- v1.1.15: Show release version tags instead of commit hashes
**Commits:** c82d3ac, 81800a7, 509a385, 684ec28, 62dc47c (2026-01-23)
**Versions:** v1.1.15 - v1.1.18

### Enhancement: Boot screen progress visibility
**Request:** Show update progress on Plymouth boot screen to indicate system is working
**Implementation:** Added Plymouth message commands to sync and update scripts
- Display current commit version during sync
- Show progress for git operations, config, packages, display updates
- Provides visual feedback that prevents users thinking system is hung
- Messages appear at default Plymouth message location
**Commit:** 4531679 (2026-01-23)
**Version:** v1.1.14

## Related Projects

- **hs1-kiosk:** Base image builder (use only for OS-level changes)
- **hs1-frontend:** Web application displayed on kiosks
- **cluster-apps:** Similar OTA system for Kubernetes cluster configuration
