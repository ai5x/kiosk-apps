#!/bin/bash
# Disable all remaining power management features
# For industrial kiosk - maximum reliability over power saving

LOG_FILE="/var/log/kiosk-power-mgmt.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "=== Disabling Power Management Features ==="

# 1. Set CPU governor to performance mode (max frequency always)
log "Setting CPU governor to performance mode..."
CPU_COUNT=0
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    if [ -f "$cpu/cpufreq/scaling_governor" ]; then
        CURRENT=$(cat "$cpu/cpufreq/scaling_governor")
        echo "performance" > "$cpu/cpufreq/scaling_governor" 2>/dev/null
        if [ $? -eq 0 ]; then
            NEW=$(cat "$cpu/cpufreq/scaling_governor")
            log "  $(basename $cpu): $CURRENT → $NEW"
            CPU_COUNT=$((CPU_COUNT + 1))
        else
            log "  $(basename $cpu): Failed to set governor"
        fi
    fi
done

if [ $CPU_COUNT -gt 0 ]; then
    log "✓ CPU governor set to performance on $CPU_COUNT cores"
    # Show frequency
    FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    if [ -n "$FREQ" ]; then
        FREQ_MHZ=$((FREQ / 1000))
        log "  Current CPU frequency: ${FREQ_MHZ} MHz"
    fi
else
    log "⚠ No CPU governor controls found"
fi

# 2. Disable PCI/PCIe power management
log "Disabling PCIe power management..."
PCI_COUNT=0
if [ -d /sys/bus/pci/devices ]; then
    for dev in /sys/bus/pci/devices/*; do
        if [ -f "$dev/power/control" ]; then
            CURRENT=$(cat "$dev/power/control")
            if [ "$CURRENT" != "on" ]; then
                echo "on" > "$dev/power/control" 2>/dev/null
                if [ $? -eq 0 ]; then
                    NEW=$(cat "$dev/power/control")
                    # Get device name
                    DEV_NAME=$(basename $dev)
                    DEV_DESC=$(lspci -s $DEV_NAME 2>/dev/null | cut -d: -f3- | xargs)
                    log "  $DEV_NAME ($DEV_DESC): $CURRENT → $NEW"
                    PCI_COUNT=$((PCI_COUNT + 1))
                fi
            fi
        fi
    done

    if [ $PCI_COUNT -gt 0 ]; then
        log "✓ PCIe power management disabled on $PCI_COUNT devices"
    else
        log "✓ All PCIe devices already set to 'on'"
    fi
else
    log "⚠ No PCI devices found (expected for some Pi models)"
fi

log "=== Power Management Configuration Complete ==="
log ""
