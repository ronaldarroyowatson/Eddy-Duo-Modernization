#!/usr/bin/env bash
# =============================================================================
# build-eddy-firmware.sh — Build Klipper firmware for BTT Eddy / Eddy Duo
#
# Applies the project kconfig, verifies five critical settings, compiles, and
# archives the build artefacts with a timestamp.
#
# Usage:
#   bash ~/eddy-duo/scripts/build-eddy-firmware.sh
#
# Output (archived under ~/eddy-duo/firmware-builds/):
#   klipper-eddy-YYYYMMDD_HHMMSS.uf2    — flash with flash-eddy-uf2.sh
#   klipper-eddy-YYYYMMDD_HHMMSS.elf    — debug / objdump
#   klipper-eddy-YYYYMMDD_HHMMSS.config — exact Kconfig snapshot
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
readonly KLIPPER_DIR="${HOME}/klipper"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly KCONFIG_SRC="${SCRIPT_DIR}/eddy-kconfig"
readonly OUT_DIR="${HOME}/eddy-duo/firmware-builds"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

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
# Preflight checks
# ---------------------------------------------------------------------------
printf "\n${BOLD}=== Eddy Duo Firmware Builder ===${RESET}\n"
printf "  Klipper  : %s\n" "${KLIPPER_DIR}"
printf "  Kconfig  : %s\n" "${KCONFIG_SRC}"
printf "  Timestamp: %s\n" "${TIMESTAMP}"

if [ ! -d "${KLIPPER_DIR}" ]; then
    err "${KLIPPER_DIR} not found — is Klipper installed?"
    exit 1
fi
if [ ! -f "${KCONFIG_SRC}" ]; then
    err "${KCONFIG_SRC} not found."
    exit 1
fi

cd "${KLIPPER_DIR}"

# Show current git state (non-fatal if somehow not a git repo)
hdr "Klipper git state"
git log --oneline -3 2>/dev/null || warn "Not in a git repository."

# ---------------------------------------------------------------------------
# Apply kconfig
# ---------------------------------------------------------------------------
hdr "Applying Eddy kconfig"
if [ -f .config ]; then
    ok "Backing up .config → .config.bak.${TIMESTAMP}"
    cp .config ".config.bak.${TIMESTAMP}"
fi
cp "${KCONFIG_SRC}" .config
make olddefconfig

# ---------------------------------------------------------------------------
# Verify critical settings
# ---------------------------------------------------------------------------
hdr "Verifying critical settings"
VERIFY_FAILED=0

verify_setting() {
    local key="${1}" expected="${2}" actual
    actual="$(grep "^${key}=" .config 2>/dev/null || printf 'NOT_SET')"
    if [ "${actual}" = "${key}=${expected}" ]; then
        ok "${key}=${expected}"
    else
        err "${key}: expected '${expected}', got '${actual}'"
        VERIFY_FAILED=1
    fi
}

verify_setting "CONFIG_MACH_RP2040"             "y"
verify_setting "CONFIG_RPXXXX_FLASH_START_0100" "y"
verify_setting "CONFIG_RP2040_FLASH_GENERIC_03" "y"
verify_setting "CONFIG_RP2040_STAGE2_CLKDIV"   "4"
verify_setting "CONFIG_USBSERIAL"               "y"

if [ "${VERIFY_FAILED}" -ne 0 ]; then
    err "One or more critical settings did not apply."
    err "Run 'make menuconfig' to inspect, then update eddy-kconfig."
    exit 1
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
hdr "Building firmware"
make clean
make -j"$(nproc 2>/dev/null || printf '4')"

if [ ! -f out/klipper.uf2 ]; then
    err "Build finished but klipper.uf2 is missing — unexpected."
    exit 1
fi

# ---------------------------------------------------------------------------
# Archive artefacts
# ---------------------------------------------------------------------------
hdr "Archiving build artefacts"
mkdir -p "${OUT_DIR}"
cp out/klipper.uf2 "${OUT_DIR}/klipper-eddy-${TIMESTAMP}.uf2"
cp out/klipper.elf "${OUT_DIR}/klipper-eddy-${TIMESTAMP}.elf"
cp .config         "${OUT_DIR}/klipper-eddy-${TIMESTAMP}.config"
ok "UF2:    ${OUT_DIR}/klipper-eddy-${TIMESTAMP}.uf2"
ok "ELF:    ${OUT_DIR}/klipper-eddy-${TIMESTAMP}.elf"
ok "Config: ${OUT_DIR}/klipper-eddy-${TIMESTAMP}.config"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "\n${BOLD}=== Build successful ===${RESET}\n"
printf "  Flash with: bash ~/eddy-duo/scripts/flash-eddy-uf2.sh\n\n"
