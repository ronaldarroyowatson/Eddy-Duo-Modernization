#!/usr/bin/env bash
# =============================================================================
# collect-eddy-diagnostics.sh — Capture Eddy USB/Klipper diagnostics bundle
#
# Usage:
#   bash ~/eddy-duo/scripts/collect-eddy-diagnostics.sh
#
# Output:
#   ~/eddy-duo/diagnostics/eddy-diagnostics-YYYYMMDD_HHMMSS/
# =============================================================================
set -euo pipefail

readonly TS="$(date +%Y%m%d_%H%M%S)"
readonly OUT_DIR="${HOME}/eddy-duo/diagnostics/eddy-diagnostics-${TS}"
mkdir -p "${OUT_DIR}"

run() {
    local name="$1"
    shift
    {
        echo "# Command: $*"
        echo ""
        "$@"
    } >"${OUT_DIR}/${name}.txt" 2>&1 || true
}

# System and USB state
run uname uname -a
run cmdline cat /proc/cmdline
run lsusb lsusb
run lsusb_tree lsusb -t
run serial_by_id ls -l /dev/serial/by-id
run tty_devices sh -c "ls -l /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || true"
run udev_rule cat /etc/udev/rules.d/99-eddy-usb-power.rules
run usb_power sh -c "grep -R . /sys/bus/usb/devices/*/power/control 2>/dev/null | head -n 300"

# Kernel and service logs
run kernel_recent journalctl -k --no-pager --since "2 days ago"
run klipper_service journalctl -u klipper --no-pager --since "2 days ago"

# Klipper log snapshots
run klippy_tail tail -n 500 ~/printer_data/logs/klippy.log
run klippy_errors sh -c "grep -nE 'Lost communication with MCU|Timeout with MCU|MCU error|Shutdown|Internal error|usb' ~/printer_data/logs/klippy.log | tail -n 300"

if [ -f ~/printer_data/logs/klippy.log.1 ]; then
    run klippy1_errors sh -c "grep -nE 'Lost communication with MCU|Timeout with MCU|MCU error|Shutdown|Internal error|usb' ~/printer_data/logs/klippy.log.1 | tail -n 300"
fi

printf "Diagnostics bundle created: %s\n" "${OUT_DIR}"
