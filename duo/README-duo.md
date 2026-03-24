# Eddy Duo — Development Overview

## What is the Eddy Duo?

The BTT Eddy Duo uses the same RP2040 MCU and LDC1612 inductance-to-digital converter as the standard
Eddy USB, but exposes **both channels** (CH0 and CH1) of the LDC1612 to two independent coils.

| Feature | Eddy USB | Eddy Duo |
| --- | --- | --- |
| MCU | RP2040 | RP2040 |
| LDC1612 channels used | CH0 only | CH0 + CH1 |
| Coils | 1 | 2 |
| Temperature sensor | GPIO26 (NTC 3950) | GPIO26 (NTC 3950) |
| Flash chip | GENERIC_03H CLKDIV 4 | GENERIC_03H CLKDIV 4 |
| Bootloader | None | None |

## Firmware Build Parameters (menuconfig)

These are the exact Klipper `make menuconfig` settings required:

```text
Micro-controller Architecture:  Raspberry Pi RP2040
Bootloader offset:              No bootloader
Flash chip:                     GENERIC_03H with CLKDIV of 4
```

> [!WARNING]
> Using the wrong flash chip setting (default CLKDIV 2 or wrong chip) will result in unreliable
> USB enumeration on power-up. The probe will occasionally fail to start. Always use CLKDIV 4.

## Key Source Files in Klipper

These are the files relevant to the Duo that live in the Klipper source tree (`~/klipper`):

| File | Role |
| --- | --- |
| `src/rp2040/main.c` | RP2040 MCU entry point |
| `src/rp2040/usbserial.c` | USB CDC serial implementation |
| `src/generic/i2c.c` | Generic I2C layer |
| `src/ldc1612.c` | LDC1612 driver (MCU side) |
| `klippy/extras/probe_eddy_current.py` | Klipper host-side eddy probe logic |
| `klippy/extras/ldc1612.py` | Host-side LDC1612 register abstraction |

## Duo-Specific Changes Required in Klipper

### 1. `src/ldc1612.c` — Enable both channels

The current MCU driver initializes LDC1612 in **single-channel mode** (CH0 only).
For the Duo, both channels must be initialized and sampled.

Key registers to configure for both channels:

- `LDC1612_CH0_RCOUNT` / `LDC1612_CH1_RCOUNT` — conversion reference count
- `LDC1612_CH0_OFFSET` / `LDC1612_CH1_OFFSET` — channel offset
- `LDC1612_CH0_CONFIG` / `LDC1612_CH1_CONFIG` — channel drive current
- `LDC1612_MUX_CONFIG` — multiplexer: must select BOTH channels (not single-channel autoscan)
- `LDC1612_CONFIG` — must enable SLEEP_MODE=0 and AUTOSCAN on both channels

### 2. `klippy/extras/probe_eddy_current.py` — Dual-channel support

The host-side Python needs to:

- Accept a second channel's readings
- Either average CH0 + CH1 for improved noise rejection, or expose them independently
- Handle two independent Z-offset calibrations if the two coils are at different heights

### 3. Configuration

The Duo needs either:

- A new `[probe_eddy_duo]` section type, OR
- Two `[probe_eddy_current]` sections with `i2c_address` set to the two channel addresses

## Development Workflow

See [../scripts/README-scripts.md](../scripts/README-scripts.md) for the full
build → flash → test workflow that runs entirely on the Raspberry Pi.

For RP2040 firmware updates, the preferred path is now a software bootloader
request over the existing USB serial link followed by `picotool` flashing.
That avoids opening the toolhead just to press BOOTSEL. Manual BOOTSEL entry is
still the fallback if the MCU is already hung and not responding on USB.

## Known Issues / Drift from Upstream

1. **USB enumeration** — intermittent failure to enumerate on cold boot is caused by wrong
   flash clock divider. Confirmed fix: `GENERIC_03H CLKDIV 4`.

2. **ADC sampling rate** — the LDC1612 reference count (`RCOUNT`) controls sampling time.
   The current Klipper mainline value may not be optimal for the Duo's coil geometry.
   Target: stable readings at ≥ 250 Hz per channel.

3. **Coil timing** — single-channel mode uses continuous conversion. Dual-channel autoscan
   introduces a small dead time between CH0 and CH1 samples. This must be accounted for
   in the bed mesh interpolation logic.

4. **Python venv** — Klipper must run in a Python 3 virtualenv. Python 2 venvs will fail
   with `split() takes no keyword arguments`. Use KIAUH to rebuild if needed.

5. **MCU disconnect behavior** — upstream Klipper treats loss of communication
   with any configured MCU as a printer shutdown condition. An Eddy USB that
   disappears mid-print will currently stop the print even if the probe is not
   actively being used.
