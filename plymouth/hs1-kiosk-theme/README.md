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

- `STAGE:0` through `STAGE:5` - Mark stage as complete and move to next
- `UPDATE_STATUS:no_updates` - Display "Already running the latest version" (gray)
- `UPDATE_STATUS:applied` - Display "Updates applied" (green)

## Checklist Stages

0. Starting system
1. Checking for updates
2. Loading core services
3. Starting HS1 services
4. Final startup checks
5. System ready

After stage 5 completes, Plymouth exits and Chromium kiosk takes over.
