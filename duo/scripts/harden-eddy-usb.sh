#!/usr/bin/env bash
# =============================================================================
# harden-eddy-usb.sh — Improve Eddy USB link stability on Raspberry Pi hosts
#
# What this script does:
#   1. Disables USB autosuspend globally via kernel cmdline
#   2. Adds a udev rule forcing power/control=on for Klipper USB MCUs (1d50:614e)
#      and RP2040 bootloader devices (2e8a:*)
#   3. Disables per-device autosuspend in sysfs where supported
#   4. Reloads udev rules and applies them to currently connected USB devices
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
readonly UDEV_RULE_FILE="/etc/udev/rules.d/99-klipper-usb-stability.rules"
readonly AUTOSUSPEND_ARG="usbcore.autosuspend=-1"
readonly QUIRK_ARG="usbcore.quirks=1d50:614e:k"

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
    local updated="${current}"

    if printf '%s' "${updated}" | grep -q "${AUTOSUSPEND_ARG}"; then
        ok "${AUTOSUSPEND_ARG} already present"
    else
        updated="${updated} ${AUTOSUSPEND_ARG}"
        ok "Will add ${AUTOSUSPEND_ARG}"
        REBOOT_REQUIRED=1
    fi

    if printf '%s' "${updated}" | grep -q "${QUIRK_ARG}"; then
        ok "${QUIRK_ARG} already present"
    else
        updated="${updated} ${QUIRK_ARG}"
        ok "Will add ${QUIRK_ARG}"
        REBOOT_REQUIRED=1
    fi

    printf '%s\n' "${updated}" | sudo tee "${CMDLINE_FILE}" >/dev/null
}

install_udev_rule() {
    hdr "Udev power rule"
    sudo tee "${UDEV_RULE_FILE}" >/dev/null <<'EOF'
# Keep active Klipper USB MCUs and RP2040 bootloader devices in full-power mode.
# Klipper USB MCUs usually enumerate as 1d50:614e (OpenMoko VID).
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="614e", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="614e", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="614e", TEST=="power/autosuspend_delay_ms", ATTR{power/autosuspend_delay_ms}="-1"
# RP2040 BOOTSEL mode (UF2/bootrom) usually enumerates as 2e8a:*.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", TEST=="power/control", ATTR{power/control}="on"
EOF
    ok "Installed ${UDEV_RULE_FILE}"

    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb
    ok "Reloaded and triggered udev rules"
}

report_connected_devices() {
    hdr "Connected Klipper USB devices"
    local found=0
    while IFS= read -r line; do
        found=1
        printf '  %s\n' "${line}"
    done < <(lsusb | grep -Ei '1d50:614e|2e8a:' || true)

    if [ "${found}" -eq 0 ]; then
        warn "No Klipper/RP2040 USB devices currently detected (VID 1d50 or 2e8a)."
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
