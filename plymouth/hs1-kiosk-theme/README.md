# HS1 Kiosk Plymouth Theme

This theme provides boot progress checklist display for kiosk-apps.

## Files

- `hs1-kiosk-theme.plymouth` - Plymouth theme configuration
- `hs1-kiosk-theme.script` - Plymouth theme script with 6-stage checklist
- `logo.png` - **NOT included in repo** - Deployed manually on kiosk

## Installation

The Plymouth theme files are deployed automatically via OTA updates by `apply-updates.sh`.

The logo.png file must already exist on the kiosk at `/usr/share/plymouth/themes/hs1-kiosk-theme/logo.png`.

## Display Orientation

This theme is designed for **90° clockwise physical rotation**:
- Framebuffer renders in landscape (1920x1080)
- Physical screen is rotated 90° clockwise to portrait
- Plymouth text appears rotated 90° CW on physical screen
- Items spread horizontally in landscape appear vertically in portrait

**Boot configuration:**
- `fbcon=rotate:1` in cmdline.txt (console rotation only, Plymouth doesn't respect this)
- `display_rotate=3` in config.txt (physical display rotation 270° = 90° CW)

**Spacing:** Uses 220px horizontal spacing in landscape to prevent overlapping after text rotation (landscape text width becomes portrait text height when rotated 90° CW).

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

## Layout

The theme uses a simple vertical layout that works with any resolution:
- Logo centered horizontally at top (y=100)
- Checklist left-aligned (x=80) below logo (y=400)
- Vertical spacing: 50px per item
- Spinner indicator moves vertically to show current stage
- Detail messages indented below stage 1 (update check)

After stage 5 completes, Plymouth exits and Chromium kiosk takes over.
