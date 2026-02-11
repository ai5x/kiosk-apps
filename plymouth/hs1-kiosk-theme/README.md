# HS1 Kiosk Plymouth Theme

This theme provides boot progress checklist display for kiosk-apps.

## Files

- `hs1-kiosk-theme.script` - Plymouth theme script with 6-stage checklist
- `logo.png` - **NOT included in repo** - Deployed manually on kiosk (portrait orientation specific)

## Installation

The Plymouth theme script is deployed automatically via OTA updates by `apply-updates.sh`.

The logo.png file must already exist on the kiosk at `/usr/share/plymouth/themes/hs1-kiosk-theme/logo.png`.

**IMPORTANT**: Do NOT replace the kiosk's logo.png file. It is specifically sized/oriented for portrait display (1080x1920).

## Message Protocol

The theme responds to these Plymouth messages sent by bootstrap scripts:

### Stage Completion
- `STAGE:0` through `STAGE:5` - Mark stage as complete and move to next

### Update Details (shown during stage 1 - Checking for updates)
- `UPDATE_CHECK` - Clear previous update details
- `UPDATE_CURRENT:v1.2.3` - Show current version
- `UPDATE_REMOTE:v1.2.4` - Show available remote version
- `UPDATE_DOWNLOADING` - Show "Downloading update..." message
- `UPDATE_APPLYING` - Show "Applying update..." message
- `UPDATE_STATUS:no_updates` - Display "No updates found" (gray)
- `UPDATE_STATUS:applied` - Display "Update complete ✓" (green)

## Checklist Stages

0. Starting system
1. Checking for updates (with detailed version information)
2. Loading configuration
3. Installing packages
4. Configuring display
5. System ready

## Portrait Display Optimization

This theme is optimized for portrait display (1080x1920):
- Left-aligned checklist at x=80
- Larger vertical spacing (50px per item)
- Logo positioned higher (y=100)
- Detail messages indented under "Checking for updates"

After stage 5 completes, Plymouth exits and Chromium kiosk takes over.
