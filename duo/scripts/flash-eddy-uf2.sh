#!/usr/bin/env bash
# =============================================================================
# flash-eddy-uf2.sh — Flash Klipper firmware to BTT Eddy / Eddy Duo (RP2040)
#
# Uses picotool (direct USB protocol), avoiding mass-storage race conditions.
# By default, requests BOOTSEL mode over the live serial link without touching
# the physical button.  Use --manual when the probe is hung.
#
# Usage:
#   bash ~/eddy-duo/scripts/flash-eddy-uf2.sh [--manual] [--help]
#
# Options:
#   --manual   Skip the software bootloader request.  Print instructions and
#              wait for the device to be put into BOOTSEL mode by hand.
#   --help     Show this message and exit.
#
# Environment overrides:
#   EDDY_MCU_NAME   Klipper MCU section name to look up.  Default: "eddy"
#   EDDY_SERIAL     Full path to the Eddy serial device.  Overrides auto-detect.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
readonly KLIPPER_DIR="${HOME}/klipper"
readonly KLIPPER_CONFIG_DIR="${HOME}/printer_data/config"
readonly EDDY_MCU_NAME="${EDDY_MCU_NAME:-eddy}"
readonly BOOTSEL_VID_PID="2e8a:0003"
readonly UF2="${KLIPPER_DIR}/out/klipper.uf2"
readonly BOOTSEL_WAIT_SECS=10   # seconds to wait for BOOTSEL device
readonly ENUM_WAIT_SECS=20      # seconds to wait for post-flash re-enumeration
# Chip IDs of other RP2040 boards on this printer that are NOT the Eddy.
# The nhk Nitehawk toolboard ID is excluded from auto-detection.
readonly EXCLUDE_SERIALS="3232323236199C3A"

# ---------------------------------------------------------------------------
# Terminal colour — disabled automatically when stdout is not a tty
# ---------------------------------------------------------------------------
if [ -t 1 ] && tput setaf 1 >/dev/null 2>&1; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BOLD="$(tput bold)"
    RESET="$(tput sgr0)"
else
    RED="" GREEN="" YELLOW="" BOLD="" RESET=""
fi

ok()   { printf "  ${GREEN}OK${RESET}  %s\n"   "$*"; }
warn() { printf "  ${YELLOW}!!${RESET}  %s\n"   "$*"; }
err()  { printf "${RED}ERROR${RESET}: %s\n" "$*" >&2; }
hdr()  { printf "\n${BOLD}--- %s ---${RESET}\n" "$*"; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
MANUAL=0

usage() {
    cat <<'EOF'
Usage: flash-eddy-uf2.sh [--manual] [--help]

Options:
  --manual   Skip the automatic software bootloader request.
             Waits for the device to be put into BOOTSEL mode by hand:
               1. Unplug the Eddy USB cable
               2. Hold the BOOTSEL button (next to the USB connector)
               3. While holding, plug the USB cable back in
               4. Release the button
  --help     Show this message and exit.

Environment overrides:
  EDDY_MCU_NAME   Klipper MCU section name to look up  (default: "eddy")
  EDDY_SERIAL     Full path to the Eddy serial device   (overrides auto-detect)
EOF
    exit 0
}

for arg in "$@"; do
    case "${arg}" in
        --manual)    MANUAL=1 ;;
        --help|-h)   usage ;;
        *) err "Unknown option: ${arg}"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Search Klipper config files for the Eddy MCU serial path.
# Sets nothing and returns 1 if not found.
find_eddy_serial() {
    local candidate result=""

    # Honour an explicit environment override first
    if [ -n "${EDDY_SERIAL:-}" ] && [ -e "${EDDY_SERIAL}" ]; then
        printf '%s' "${EDDY_SERIAL}"
        return 0
    fi

    # Search config files in priority order; return on first match
    for candidate in \
        "${KLIPPER_CONFIG_DIR}/device-map.cfg" \
        "${KLIPPER_CONFIG_DIR}/printer.cfg"; do
        [ -f "${candidate}" ] || continue
        result="$(awk -v mcu="${EDDY_MCU_NAME}" '
            $0 == "[mcu " mcu "]" { in_section=1; next }
            /^\[/               { in_section=0 }
            in_section && $1 == "serial:" { print $2; exit }
        ' "${candidate}")"
        if [ -n "${result}" ]; then
            printf '%s' "${result}"
            return 0
        fi
    done
    return 1
}

# Return 0 if the RP2040 BOOTSEL device is visible via lsusb.
bootsel_present() {
    lsusb 2>/dev/null | grep -q "${BOOTSEL_VID_PID}"
}

# Poll for a BOOTSEL device for up to BOOTSEL_WAIT_SECS seconds.
wait_for_bootsel() {
    local i
    for i in $(seq 1 "${BOOTSEL_WAIT_SECS}"); do
        bootsel_present && return 0
        sleep 1
    done
    return 1
}

# Poll for the Eddy's Klipper serial device after flashing.
# Sets the global FOUND_SERIAL on success; returns 1 on timeout.
FOUND_SERIAL=""
wait_for_enumeration() {
    local i serial
    for i in $(seq 1 "${ENUM_WAIT_SECS}"); do
        if [ -n "${EDDY_SERIAL_PATH}" ]; then
            serial="$(basename "${EDDY_SERIAL_PATH}")"
            if [ -e "/dev/serial/by-id/${serial}" ]; then
                FOUND_SERIAL="${serial}"
                return 0
            fi
        else
            serial="$(ls /dev/serial/by-id/ 2>/dev/null \
                     | grep "Klipper_rp2040" \
                     | grep -v "${EXCLUDE_SERIALS}" \
                     | head -1 || true)"
            if [ -n "${serial}" ]; then
                FOUND_SERIAL="${serial}"
                return 0
            fi
        fi
        [ -t 1 ] && printf "  (%2d/%d) waiting for enumeration...\r" \
            "${i}" "${ENUM_WAIT_SECS}"
        sleep 1
    done
    [ -t 1 ] && printf "%*s\r" "${COLUMNS:-80}" ""  # clear progress line
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
printf "\n${BOLD}=== Eddy Firmware Flasher (picotool) ===${RESET}\n"

# Preflight: confirm UF2 exists before touching the system
if [ ! -f "${UF2}" ]; then
    err "${UF2} not found.  Run build-eddy-firmware.sh first."
    exit 1
fi
ok "UF2 found: ${UF2}"

# Initialise before conditional assignments so set -u never fires on them
RESTART_KLIPPER=0
EDDY_SERIAL_PATH=""

# Stop Klipper so it does not hold the serial device open
if systemctl is-active --quiet klipper 2>/dev/null; then
    hdr "Stopping Klipper"
    sudo systemctl stop klipper
    RESTART_KLIPPER=1
fi

# ---- Bootloader entry -------------------------------------------------------
hdr "Entering BOOTSEL mode"

if bootsel_present; then
    ok "Device already in BOOTSEL mode."
elif [ "${MANUAL}" -eq 1 ]; then
    warn "Manual mode — skipping software bootloader request."
    printf "\n  Enter BOOTSEL mode now:\n"
    printf "    1. Unplug the Eddy USB cable\n"
    printf "    2. Hold the BOOTSEL button (next to the USB connector)\n"
    printf "    3. While holding, plug the USB cable back in\n"
    printf "    4. Release the button\n\n"
    printf "  Waiting up to %d seconds...\n" "${BOOTSEL_WAIT_SECS}"
    if ! wait_for_bootsel; then
        err "Eddy did not appear in BOOTSEL mode within ${BOOTSEL_WAIT_SECS}s."
        err "Verify with: lsusb | grep ${BOOTSEL_VID_PID}"
        [ "${RESTART_KLIPPER}" -eq 1 ] && sudo systemctl start klipper
        exit 1
    fi
    ok "BOOTSEL device detected."
else
    # Automatic path: request BOOTSEL over the live serial connection
    EDDY_SERIAL_PATH="$(find_eddy_serial 2>/dev/null || true)"
    if [ -n "${EDDY_SERIAL_PATH}" ] && [ -e "${EDDY_SERIAL_PATH}" ]; then
        ok "Eddy serial: ${EDDY_SERIAL_PATH}"
        printf "  Requesting RP2040 USB bootloader over serial...\n"
        (
            cd "${KLIPPER_DIR}/scripts"
            python3 -c "import flash_usb as u; u.enter_bootloader('${EDDY_SERIAL_PATH}')"
        ) || true   # failure is non-fatal; we check for the device below

        if ! wait_for_bootsel; then
            err "Remote bootloader request did not produce a BOOTSEL device."
            err "If the Eddy is hung, re-run with --manual and press the button."
            [ "${RESTART_KLIPPER}" -eq 1 ] && sudo systemctl start klipper
            exit 1
        fi
        ok "BOOTSEL entered remotely."
    else
        err "Eddy serial device not found — cannot request bootloader remotely."
        err "Re-run with --manual and enter BOOTSEL mode by hand."
        [ "${RESTART_KLIPPER}" -eq 1 ] && sudo systemctl start klipper
        exit 1
    fi
fi

printf "  Detected: %s\n" "$(lsusb 2>/dev/null | grep "${BOOTSEL_VID_PID}" | head -1)"

# ---- Flash ------------------------------------------------------------------
hdr "Flashing ${UF2}"
# picotool -x: load and immediately execute (reboot into application)
sudo picotool load -x "${UF2}"

# ---- Wait for re-enumeration ------------------------------------------------
hdr "Waiting for Eddy to re-enumerate as Klipper MCU"
if wait_for_enumeration; then
    [ -t 1 ] && printf "%*s\r" "${COLUMNS:-80}" ""
    ok "Eddy enumerated: /dev/serial/by-id/${FOUND_SERIAL}"
else
    warn "Eddy did not appear in /dev/serial/by-id/ within ${ENUM_WAIT_SECS}s."
    printf "  Current entries in /dev/serial/by-id/:\n"
    ls /dev/serial/by-id/ 2>/dev/null | sed 's/^/    /' || printf "    (empty)\n"
fi

# ---- Restart Klipper --------------------------------------------------------
if [ "${RESTART_KLIPPER}" -eq 1 ]; then
    hdr "Restarting Klipper"
    sudo systemctl start klipper
    sleep 3
    if systemctl is-active --quiet klipper 2>/dev/null; then
        ok "Klipper running"
    else
        warn "Klipper failed to start — check: journalctl -u klipper -n 30"
    fi
fi

# ---- Summary ----------------------------------------------------------------
printf "\n${BOLD}=== Done ===${RESET}\n"
[ -n "${FOUND_SERIAL}" ] && printf "  Serial: /dev/serial/by-id/%s\n" "${FOUND_SERIAL}"
printf "\n"
