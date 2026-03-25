#!/usr/bin/env bash
# =============================================================================
# harden-eddy-usb.sh — Improve Eddy USB link stability on Raspberry Pi hosts
#
# What this script does:
#   1. Disables USB autosuspend globally via kernel cmdline
#   2. Adds a udev rule forcing power/control=on for RP2040 devices (2e8a)
#   3. Reloads udev rules and applies them to currently connected USB devices
#
# Usage:
#   bash ~/eddy-duo/scripts/harden-eddy-usb.sh
#
# Notes:
# - Requires sudo for system changes.
# - Reboot is required if cmdline was updated.
# =============================================================================
set -euo pipefail

readonly CMDLINE_FILE="/boot/firmware/cmdline.txt"
readonly UDEV_RULE_FILE="/etc/udev/rules.d/99-eddy-usb-power.rules"
readonly AUTOSUSPEND_ARG="usbcore.autosuspend=-1"

if [ -t 1 ] && tput setaf 1 >/dev/null 2>&1; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BOLD="$(tput bold)"
    RESET="$(tput sgr0)"
else
    RED="" GREEN="" YELLOW="" BOLD="" RESET=""
fi

ok()   { printf "  ${GREEN}OK${RESET}  %s\n" "$*"; }
warn() { printf "  ${YELLOW}!!${RESET}  %s\n" "$*"; }
err()  { printf "${RED}ERROR${RESET}: %s\n" "$*" >&2; }
hdr()  { printf "\n${BOLD}--- %s ---${RESET}\n" "$*"; }

require_sudo() {
    if ! sudo -n true 2>/dev/null; then
        warn "Sudo password may be required for system changes."
    fi
}

update_cmdline() {
    hdr "Kernel cmdline"
    if [ ! -f "${CMDLINE_FILE}" ]; then
        err "cmdline file not found: ${CMDLINE_FILE}"
        exit 1
    fi

    local current
    current="$(sudo cat "${CMDLINE_FILE}")"
    if printf '%s' "${current}" | grep -q "${AUTOSUSPEND_ARG}"; then
        ok "${AUTOSUSPEND_ARG} already present"
        return 0
    fi

    local updated
    updated="${current} ${AUTOSUSPEND_ARG}"
    printf '%s\n' "${updated}" | sudo tee "${CMDLINE_FILE}" >/dev/null
    ok "Added ${AUTOSUSPEND_ARG} to ${CMDLINE_FILE}"
    REBOOT_REQUIRED=1
}

install_udev_rule() {
    hdr "Udev power rule"
    sudo tee "${UDEV_RULE_FILE}" >/dev/null <<'EOF'
# Keep active Klipper USB MCUs and RP2040 bootloader devices in full-power mode
# Klipper USB MCUs usually enumerate as 1d50:614e (OpenMoko VID).
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="614e", TEST=="power/control", ATTR{power/control}="on"
# RP2040 BOOTSEL mode (UF2/bootrom) usually enumerates as 2e8a:*.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", TEST=="power/control", ATTR{power/control}="on"
EOF
    ok "Installed ${UDEV_RULE_FILE}"

    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb
    ok "Reloaded and triggered udev rules"
}

report_connected_devices() {
    hdr "Connected RP2040 devices"
    local found=0
    while IFS= read -r line; do
        found=1
        printf '  %s\n' "${line}"
    done < <(lsusb | grep -i '2e8a' || true)

    if [ "${found}" -eq 0 ]; then
        warn "No RP2040 USB devices currently detected (VID 2e8a)."
    fi
}

main() {
    REBOOT_REQUIRED=0
    printf "\n${BOLD}=== Eddy USB Link Hardening ===${RESET}\n"
    require_sudo
    update_cmdline
    install_udev_rule
    report_connected_devices

    if [ "${REBOOT_REQUIRED}" -eq 1 ]; then
        printf "\n${YELLOW}Reboot required${RESET}: run 'sudo reboot' to apply kernel cmdline changes.\n"
    else
        printf "\n${GREEN}No reboot required${RESET}: kernel cmdline already configured.\n"
    fi

    printf "\nAdditional physical checks:\n"
    printf "  - Keep Eddy USB cable separated from stepper/heater bundles (do not tie together).\n"
    printf "  - Prefer a short, shielded USB cable with ferrite choke if available.\n"
    printf "  - Use a stable Pi USB port (avoid loose adapters).\n\n"
}

main "$@"
