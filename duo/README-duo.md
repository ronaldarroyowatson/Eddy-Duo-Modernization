# Eddy Duo in This Fork

This document explains what this fork adds on top of the original BIGTREETECH Eddy repository,
what remains upstream behavior, and the exact steps to run Eddy Duo reliably.

## Scope and Ownership

### Upstream (BIGTREETECH)

- Hardware design and baseline Eddy documentation
- Original sample configs and general calibration procedure
- Main README at repository root

### This fork (Eddy-Duo-Modernization)

- Dedicated Duo-focused scripts in duo/scripts:
  - setup-eddy-dev.sh
  - build-eddy-firmware.sh
  - flash-eddy-uf2.sh
- Reliable RP2040 build profile captured in duo/scripts/eddy-kconfig
- Remote BOOTSEL flash path (software request first, manual fallback)
- Duo sample configs:
  - duo/sample-eddy-duo.cfg
  - duo/sample-eddy-duo-homing.cfg
- This focused operations guide

## Hardware and Firmware Facts

| Feature | Eddy USB | Eddy Duo |
| --- | --- | --- |
| MCU | RP2040 | RP2040 |
| LDC1612 channels used | CH0 only | CH0 + CH1 |
| Coils | 1 | 2 |
| Temperature sensor | GPIO26 (NTC 3950) | GPIO26 (NTC 3950) |
| Required flash chip profile | GENERIC_03H CLKDIV 4 | GENERIC_03H CLKDIV 4 |
| Bootloader offset | No bootloader | No bootloader |

Required Klipper menuconfig values:

```text
Micro-controller Architecture:  Raspberry Pi RP2040
Bootloader offset:              No bootloader
Flash chip:                     GENERIC_03H with CLKDIV of 4
```

WARNING: Using the wrong flash-chip profile can compile successfully but produce intermittent
USB startup failures after reboot or power cycle.

## Quick Start for Eddy Duo

Run these steps on the Raspberry Pi host.

1. One-time environment setup:

```bash
bash ~/eddy-duo/scripts/setup-eddy-dev.sh
```

1. Build firmware with validated settings:

```bash
bash ~/eddy-duo/scripts/build-eddy-firmware.sh
```

1. Flash firmware (remote BOOTSEL path):

```bash
bash ~/eddy-duo/scripts/flash-eddy-uf2.sh
```

1. If the probe is hung and cannot accept software BOOTSEL:

```bash
bash ~/eddy-duo/scripts/flash-eddy-uf2.sh --manual
```

1. Apply one Duo sample config:

- Use duo/sample-eddy-duo.cfg for probe-only mode
- Use duo/sample-eddy-duo-homing.cfg for probe plus Z homing

1. Update machine-specific values in your printer config:

- mcu serial path
- x_offset and y_offset
- mesh_min and mesh_max
- home_xy_position (for homing variant)

1. Re-run the normal Eddy calibration sequence:

- LDC_CALIBRATE_DRIVE_CURRENT
- PROBE_EDDY_CURRENT_CALIBRATE_AUTO (or manual equivalent)
- BED_MESH_CALIBRATE
- TEMPERATURE_PROBE_CALIBRATE (USB workflows when needed)

## What Changed Versus Original Flash Flow

Original root README flow uses manual BOOTSEL press and make flash.

This fork adds a safer operator flow:

1. request bootloader over live USB serial
2. flash with picotool
3. verify Eddy re-enumeration
4. restart Klipper

Manual BOOTSEL is still supported via --manual for recovery scenarios.

## Current Limitations and Important Notes

1. Upstream Klipper currently treats loss of any configured MCU as a shutdown event.
   If Eddy disconnects mid-print, the print can stop.

2. True dual-channel behavior in mainline may still require deeper LDC1612 path changes,
   depending on your intended averaging/synchronization model.

3. Keep Klipper itself on mainline in ~/klipper. This fork does not vendor Klipper source.

## Updating After Future Klipper Releases

Typical upgrade cycle:

```bash
cd ~/klipper
git pull
bash ~/eddy-duo/scripts/build-eddy-firmware.sh
bash ~/eddy-duo/scripts/flash-eddy-uf2.sh
```

If Klipper changes config symbols or Eddy probe config syntax, build-time verification and
runtime config errors should surface quickly.

## Key Files in This Fork

- duo/scripts/setup-eddy-dev.sh
- duo/scripts/build-eddy-firmware.sh
- duo/scripts/flash-eddy-uf2.sh
- duo/scripts/eddy-kconfig
- duo/sample-eddy-duo.cfg
- duo/sample-eddy-duo-homing.cfg
