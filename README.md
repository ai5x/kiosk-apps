# Kiosk-Apps

Over-the-air (OTA) update system for HS1 kiosk devices. Automatically syncs configuration and applies updates on boot.

## Overview

`kiosk-apps` is a git-based configuration management system for HS1 kiosk devices, similar to how `cluster-apps` manages the Kubernetes cluster. It enables centralized management of kiosk configuration and automatic updates without manual intervention.

### Features

- **Auto-Sync on Boot**: Checks for updates every time the kiosk boots
- **Git-Based**: Version-controlled configuration with full history
- **Idempotent**: Safe to run multiple times, only applies changes when needed
- **Package Management**: Can trigger OS package updates
- **Automatic Restart**: Restarts kiosk services when configuration changes
- **Rollback Support**: Keeps backup of previous configuration
- **Secure**: Uses read-only GitHub PAT for authentication

## Architecture

```
Boot Sequence:
  1. kiosk-apps-sync.service starts
  2. sync-and-update.sh pulls latest from git
  3. apply-updates.sh applies configuration changes
  4. Restart kiosk if configuration changed
  5. Continue to normal kiosk operation

Directory Structure:
  /opt/kiosk-apps/           (this git repo)
  ├── .env.local             (GitHub token - not in git)
  ├── config/
  │   ├── .env               (kiosk configuration - tracked)
  │   └── update-packages.txt (trigger for apt upgrade - tracked)
  ├── scripts/
  │   ├── start-kiosk.sh     (Chromium launcher - tracked)
  │   ├── watchdog.sh        (Browser monitor - tracked)
  │   ├── sync-and-update.sh (Git sync script)
  │   └── apply-updates.sh   (Apply changes script)
  └── systemd/
      └── kiosk-apps-sync.service

  /opt/kiosk/                (runtime kiosk directory)
  ├── .env                   (copied from kiosk-apps)
  ├── start-kiosk.sh         (copied from kiosk-apps)
  └── watchdog.sh            (copied from kiosk-apps)
```

## Installation

### On Fresh Kiosk Image

The `hs1-kiosk` image builder automatically includes kiosk-apps setup in the first-boot provisioning script. No manual installation needed.

### Manual Installation

```bash
# Clone repository
sudo git clone https://github.com/ai5x/kiosk-apps.git /opt/kiosk-apps
cd /opt/kiosk-apps

# Set up GitHub token (optional - required for private repo)
sudo cp .env.local.sample .env.local
sudo nano .env.local  # Add your GitHub PAT

# Install systemd service
sudo cp systemd/kiosk-apps-sync.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kiosk-apps-sync.service

# Run initial sync
sudo /opt/kiosk-apps/scripts/sync-and-update.sh
```

## Configuration Management

### Updating Kiosk Configuration

1. Edit `config/.env` in this repository
2. Commit and push changes:
   ```bash
   git add config/.env
   git commit -m "Update kiosk URL to new frontend"
   git push
   ```
3. On next kiosk boot (or manual trigger), changes will be applied automatically

### Updating Kiosk Scripts

1. Edit scripts in `scripts/` directory (e.g., `start-kiosk.sh`, `watchdog.sh`)
2. Commit and push:
   ```bash
   git add scripts/
   git commit -m "Add error handling to start-kiosk.sh"
   git push
   ```
3. Changes will be applied on next boot

### Triggering Package Updates

To update OS packages on kiosk:

```bash
# Create update trigger file
touch config/update-packages.txt
git add config/update-packages.txt
git commit -m "Trigger package update"
git push
```

On next boot, kiosk will:
1. Run `apt-get update && apt-get upgrade -y`
2. Remove `update-packages.txt`
3. Reboot if kernel/system packages were updated

## Manual Operations

### Manual Sync

Trigger update check without waiting for next boot:

```bash
ssh kiosk@hs1-kiosk
sudo systemctl start kiosk-apps-sync.service

# Or run directly
sudo /opt/kiosk-apps/scripts/sync-and-update.sh
```

### Check Sync Status

```bash
# View last sync log
sudo journalctl -u kiosk-apps-sync.service -n 100

# View log file
sudo tail -f /var/log/kiosk-apps-sync.log
```

### Force Configuration Update

```bash
ssh kiosk@hs1-kiosk
cd /opt/kiosk-apps
sudo git pull
sudo /opt/kiosk-apps/scripts/apply-updates.sh
```

### Rollback Configuration

```bash
ssh kiosk@hs1-kiosk

# List backups
ls -l /opt/kiosk/.env.backup.*

# Restore from backup
sudo cp /opt/kiosk/.env.backup.20250120-143022 /opt/kiosk/.env
sudo systemctl restart lightdm
```

## Authentication

### GitHub Personal Access Token (PAT)

For private repositories, create a read-only PAT:

1. Go to https://github.com/settings/tokens
2. Generate new token (classic)
3. Permissions: `repo` (read-only)
4. Copy token to `/opt/kiosk-apps/.env.local`:
   ```bash
   GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

**Security Note**: Use the same read-only PAT as `cluster-apps` for consistency. This token only needs read access to pull updates.

### Token Management

The token is:
- Stored in `/opt/kiosk-apps/.env.local` (NOT in git)
- Read by systemd service via `EnvironmentFile`
- Used only for `git fetch` operations
- Never logged or exposed in output

## Update Workflow

### Typical Update Flow

```
Developer              GitHub                Kiosk Device
    |                    |                         |
    | 1. Edit config     |                         |
    |------------------>|                         |
    | 2. Commit & push   |                         |
    |------------------>|                         |
    |                    |                         |
    |                    |    3. Boot / Timer      |
    |                    |<------------------------|
    |                    | 4. Git pull             |
    |                    |------------------------>|
    |                    |                         |
    |                    |    5. Apply updates     |
    |                    |                         |
    |                    |    6. Restart kiosk     |
    |                    |                         |
```

### What Gets Updated

| File Type | Trigger | Action |
|-----------|---------|--------|
| `config/.env` | On change | Copy to `/opt/kiosk/.env`, restart kiosk |
| `scripts/start-kiosk.sh` | On change | Copy to `/opt/kiosk/`, restart kiosk |
| `scripts/watchdog.sh` | On change | Copy to `/opt/kiosk/`, restart watchdog |
| `config/update-packages.txt` | If exists | Run `apt-get upgrade`, reboot if needed |

## Monitoring

### Service Status

```bash
# Check if service is enabled
systemctl is-enabled kiosk-apps-sync.service

# Check service status
systemctl status kiosk-apps-sync.service

# View recent logs
journalctl -u kiosk-apps-sync.service --since today
```

### Update History

```bash
# View git commit history
cd /opt/kiosk-apps
git log --oneline --graph

# View what changed in last update
git diff HEAD~1 HEAD

# View configuration changes
git log -p config/.env
```

### Troubleshooting

#### Updates Not Applying

```bash
# Check network connectivity
ping github.com

# Check GitHub token
sudo cat /opt/kiosk-apps/.env.local

# Manual sync to see errors
sudo /opt/kiosk-apps/scripts/sync-and-update.sh
```

#### Service Failing

```bash
# Check service logs
sudo journalctl -u kiosk-apps-sync.service -xe

# Check permissions
ls -la /opt/kiosk-apps
ls -la /opt/kiosk

# Verify systemd service
systemctl cat kiosk-apps-sync.service
```

#### Configuration Not Taking Effect

```bash
# Verify config was copied
diff /opt/kiosk-apps/config/.env /opt/kiosk/.env

# Check if kiosk restarted
journalctl -u lightdm.service --since "10 minutes ago"

# Manually restart kiosk
sudo systemctl restart lightdm
```

## Development

### Testing Changes Locally

```bash
# Make changes to config
nano config/.env

# Test apply script without git pull
sudo /opt/kiosk-apps/scripts/apply-updates.sh

# Verify kiosk is using new config
sudo cat /opt/kiosk/.env
```

### Creating New Configuration Options

1. Add new variable to `config/.env`
2. Update consumer scripts (`start-kiosk.sh`, etc.) to use new variable
3. Test locally
4. Commit and push both files together

## Security Considerations

- **GitHub Token**: Use read-only PAT, never commit to git
- **.env.local**: Excluded from git via `.gitignore`
- **Service Permissions**: Runs as root (required for system changes)
- **Network**: Only outbound HTTPS to GitHub
- **Validation**: Scripts validate file existence before copying

## Comparison to cluster-apps

| Feature | cluster-apps | kiosk-apps |
|---------|--------------|------------|
| Purpose | K8s cluster deployment | Kiosk configuration |
| Update Trigger | Boot + timer | Boot only |
| Package Management | K3s, Helm, kubectl | apt packages |
| Restart Mechanism | Helm upgrades | systemctl restart |
| Credentials | GHCR token | GitHub PAT (same) |
| Target Systems | node1, node2, node3 | kiosk devices |

## Related Projects

- **hs1-kiosk**: Image builder for kiosk SD card
- **hs1-backend**: Robot control backend
- **hs1-frontend**: Web UI (displayed by kiosk)
- **cluster-apps**: K8s cluster configuration (similar pattern)

## License

Copyright (c) 2025 AI5X

## Support

For issues or questions:
- GitHub Issues: https://github.com/ai5x/kiosk-apps/issues
- Check logs: `sudo journalctl -u kiosk-apps-sync.service -f`
