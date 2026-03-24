#!/usr/bin/env bash
# =============================================================================
# setup-eddy-dev.sh
# One-time setup of the ~/eddy-duo development workspace on the Raspberry Pi.
# Run with: bash ~/eddy-duo/scripts/setup-eddy-dev.sh
# =============================================================================
set -euo pipefail

EDDY_DEV="$HOME/eddy-duo"
KLIPPER_DIR="$HOME/klipper"

echo "=== Eddy Duo Dev Environment Setup ==="
echo ""

# 1. Verify klippy-env is Python 3
echo "--- Checking klippy-env Python version ---"
KLIPPY_PY="$HOME/klippy-env/bin/python3"
if [ ! -f "$KLIPPY_PY" ]; then
    echo "ERROR: $KLIPPY_PY not found."
    echo "Klipper venv may not exist or may be Python 2."
    echo "Use KIAUH to reinstall Klipper with Python 3."
    exit 1
fi
PY_VER=$("$KLIPPY_PY" --version 2>&1)
echo "  $KLIPPY_PY -> $PY_VER"
if echo "$PY_VER" | grep -q "Python 2"; then
    echo "ERROR: klippy-env is Python 2! Use KIAUH to reinstall with Python 3."
    exit 1
fi
echo "  OK"
echo ""

# 2. Verify ARM cross-compiler is available (for make)
echo "--- Checking build tools ---"
#!/usr/bin/env bash
# =============================================================================
# setup-eddy-dev.sh — One-time dev-environment setup for Eddy Duo on Pi
#
# Run once after cloning or copying the repo to ~/eddy-duo/:
#   bash ~/eddy-duo/scripts/setup-eddy-dev.sh
#
# What it does:
#   1. Checks required system tools (git, python3, pip3, make, gcc)
#   2. Installs picotool (apt) if not already present
#   3. Validates the Klipper Python venv
#   4. Verifies critical Klipper source files for RP2040 builds
#   5. Creates ~/eddy-duo/firmware-builds/ workspace directory
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
readonly KLIPPER_DIR="${HOME}/klipper"
readonly EDDY_DUO_DIR="${HOME}/eddy-duo"
readonly VENV_DIR="${HOME}/klippy-env"

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
# 1. Required system tools
# ---------------------------------------------------------------------------
printf "\n${BOLD}=== Eddy Duo Dev Environment Setup ===${RESET}\n"

hdr "Checking required tools"
MISSING=0
REQUIRED_TOOLS=(git python3 pip3 make gcc)
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "${tool}" &>/dev/null; then
        ok "${tool} → $(command -v "${tool}")"
    else
        err "Missing tool: ${tool}"
        MISSING=1
    fi
done
if [ "${MISSING}" -ne 0 ]; then
    err "Install missing tools: sudo apt install build-essential python3-pip git"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. picotool — used by flash-eddy-uf2.sh for software BOOTSEL + flash
# ---------------------------------------------------------------------------
hdr "picotool"
if command -v picotool &>/dev/null; then
    ok "Already installed: $(picotool version 2>&1 | head -1)"
else
    warn "Not found — installing via apt..."
    sudo apt install -y picotool
    ok "Installed: $(picotool version 2>&1 | head -1)"
fi

# ---------------------------------------------------------------------------
# 3. Klipper Python venv
# ---------------------------------------------------------------------------
hdr "Klipper Python venv"
if [ -d "${VENV_DIR}" ] && [ -f "${VENV_DIR}/bin/python" ]; then
    ok "venv: ${VENV_DIR}"
    ok "$("${VENV_DIR}/bin/python" --version 2>&1)"
else
    err "${VENV_DIR} not found — Klipper may not be installed correctly."
    err "See: https://www.klipper3d.org/Installation.html"
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Klipper source files required for RP2040 builds
# ---------------------------------------------------------------------------
hdr "Klipper RP2040 source files"
ALL_OK=1
CRITICAL_FILES=(
    "${KLIPPER_DIR}/src/rp2040/main.c"
    "${KLIPPER_DIR}/src/rp2040/bootrom.c"
    "${KLIPPER_DIR}/scripts/flash_usb.py"
    "${KLIPPER_DIR}/Makefile"
)
for f in "${CRITICAL_FILES[@]}"; do
    if [ -f "${f}" ]; then
        ok "${f}"
    else
        err "Missing: ${f}"
        ALL_OK=0
    fi
done
if [ "${ALL_OK}" -ne 1 ]; then
    err "One or more Klipper source files are missing."
    err "Run: git -C \"${KLIPPER_DIR}\" pull"
    exit 1
fi

# ---------------------------------------------------------------------------
# 5. Workspace directory
# ---------------------------------------------------------------------------
hdr "Workspace directories"
mkdir -p "${EDDY_DUO_DIR}/firmware-builds"
ok "${EDDY_DUO_DIR}/firmware-builds"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
printf "\n${BOLD}=== Setup complete ===${RESET}\n"
printf "  1. Build firmware : bash ~/eddy-duo/scripts/build-eddy-firmware.sh\n"
printf "  2. Flash Eddy     : bash ~/eddy-duo/scripts/flash-eddy-uf2.sh\n\n"
