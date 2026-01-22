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

### Trigger Package Updates

```bash
# Create update-packages.txt with package names
echo "chromium" > update-packages.txt
echo "xserver-xorg" >> update-packages.txt

git add update-packages.txt
git commit -m "Update Chromium and X server"
git push

# On next boot, apt-get will update these packages
```

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
# Check if xinput found devices
DISPLAY=:0 xinput list | grep -i touch

# Check transformation matrix
DISPLAY=:0 xinput list-props <device-id> | grep "Coordinate Transformation"

# Check autostart log for errors
cat /tmp/openbox-autostart.log
```

## Repository Structure

```
kiosk-apps/
├── config/
│   ├── .env                              # Main configuration
│   ├── xorg-modesetting.conf            # X server config
│   ├── openbox-autostart-landscape      # Landscape rotation
│   ├── openbox-autostart-portrait       # Portrait rotation (90°)
│   └── openbox-autostart-portrait-inverted  # Portrait inverted (270°)
├── scripts/
│   ├── sync-and-update.sh               # Main sync script (runs on boot)
│   ├── apply-updates.sh                 # Apply configuration changes
│   └── install-sync-service.sh          # Manual installation script
├── systemd/
│   └── kiosk-apps-sync.service          # Systemd service definition
└── README.md                            # User documentation
```

## Related Projects

- **hs1-kiosk:** Base image builder (use only for OS-level changes)
- **hs1-frontend:** Web application displayed on kiosks
- **cluster-apps:** Similar OTA system for Kubernetes cluster configuration
