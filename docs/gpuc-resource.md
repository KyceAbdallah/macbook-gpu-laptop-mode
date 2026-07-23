# GPUC Resource Notes

## Local Pattern to Look For

On T2-era dual-GPU MacBooks, the Apple graphics mux appears as an ACPI device with HID:

```text
APP000B
```

The relevant PnP/ACPI device is commonly named `GPUC`.

## Public Linux Reference

The upstream Linux `apple-gmux` driver is the most useful public reference for this hardware path:

- `drivers/platform/x86/apple-gmux.c`
- `include/linux/apple-gmux.h`

Useful constants from the Linux header:

```text
GMUX_ACPI_HID = APP000B
GMUX_MMIO_READ = 0x00
GMUX_MMIO_WRITE = 0x40
GMUX_MMIO_PORT_SELECT = 0x0e
GMUX_MMIO_COMMAND_SEND = 0x0f
GMUX_PORT_SWITCH_DISPLAY = 0x10
GMUX_PORT_SWITCH_GET_DISPLAY = 0x11
GMUX_PORT_DISCRETE_POWER = 0x50
```

Important implementation detail from Linux:

The ACPI table may allocate only 8 bytes, but the MMIO gmux access protocol uses 16 bytes.

## Interpretation

If Windows reports an `APP000B` memory resource similar to:

```text
base + 0x00 through base + 0x07
```

that is probably only the ACPI-declared part of the gmux MMIO window. Linux's MMIO path also uses:

```text
base + 0x0e  port select
base + 0x0f  command send/status
```

So a future read-only kernel probe should consider the Linux behavior, but should still start by mapping only the resource Windows reports. Expanding to 16 bytes is a separate decision and should be treated as higher risk.

## User-Mode Boundary

Normal user-mode tools can confirm the reported resource range and device binding, but they should not attempt to read physical MMIO directly. Reading gmux bytes requires a kernel component or an existing trusted driver interface.

## Sources

- Linux `apple-gmux.c`: https://github.com/torvalds/linux/blob/master/drivers/platform/x86/apple-gmux.c
- Linux `apple-gmux.h`: https://github.com/torvalds/linux/blob/master/include/linux/apple-gmux.h
- T2 Linux hybrid graphics guide: https://wiki.t2linux.org/guides/hybrid-graphics/
