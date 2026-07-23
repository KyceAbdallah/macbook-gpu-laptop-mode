# GPUC Inspector

Native read-only user-mode inspector for Apple graphics mux research.

## What It Does

- Enumerates display devices with `EnumDisplayDevicesW`.
- Enumerates present PnP devices with SetupAPI.
- Prints Apple graphics mux, AMD, and Intel device properties.
- Attempts to read allocated resources through Configuration Manager.

## What It Does Not Do

- Does not read physical MMIO.
- Does not write to MMIO, EC, ACPI, registry, drivers, or display settings.
- Does not install a driver.
- Does not require Windows Test Mode.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\native\gpuc-inspector\build.ps1
```

## Current Limitation

On the initial MacBookPro16,1 Windows test machine, Configuration Manager did not expose an allocated log configuration for `ACPI\APP000B` even though WMI reported a memory resource. For now, use the PowerShell safe report as the resource-confirming path and this native tool as an independent PnP/display binding check.
