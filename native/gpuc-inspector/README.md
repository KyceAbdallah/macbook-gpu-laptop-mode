# GPUC Inspector

Native read-only user-mode inspector for Apple graphics mux research.

## What It Does

- Enumerates display devices with `EnumDisplayDevicesW`.
- Enumerates present PnP devices with SetupAPI.
- Prints Apple graphics mux, AMD, and Intel device properties.
- Attempts to read allocated resources through Configuration Manager.
- Attempts a WMI resource fallback for `APP000B`.
- Can write Markdown and JSON reports with `--output-dir`.

## What It Does Not Do

- Does not read physical MMIO.
- Does not write to MMIO, EC, ACPI, registry, drivers, or display settings.
- Does not install a driver.
- Does not require Windows Test Mode.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\native\gpuc-inspector\build.ps1
```

## Run

Console only:

```powershell
.\native\gpuc-inspector\bin\Release\gpuc-inspector.exe
```

Console plus files:

```powershell
.\native\gpuc-inspector\bin\Release\gpuc-inspector.exe --output-dir .\captures\native-inspector\latest
```

The output directory receives:

- `gpuc-inspector.md`
- `gpuc-inspector.json`

## Current Limitation

On the initial MacBookPro16,1 Windows test machine, Configuration Manager did not expose an allocated log configuration for `ACPI\APP000B`, while WMI did report a memory resource. The current tool records both results so the mismatch is visible in one report.
