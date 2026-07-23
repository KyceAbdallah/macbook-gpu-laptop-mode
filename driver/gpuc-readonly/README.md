# GPUC Read-Only KMDF Scaffold

This folder is a design scaffold for a future read-only KMDF probe targeting Apple graphics mux ACPI devices.

It is not ready to install.

## Safety Status

Current state:

- source scaffold only,
- INF draft only,
- no signed package,
- no install script,
- no write IOCTLs,
- no default MMIO mapping,
- no default resource byte reads,
- no mux switching,
- no EC access,
- no display adapter enable/disable behavior,
- no speculative 16-byte Linux-derived read path.

The phase-1 driver policy is inventory-only. It reports resources Windows assigns to the device, but it does not map or read those resources by default.

`IOCTL_GPUC_READ_RESOURCE_BYTES` exists in the shared contract for a later phase, but the scaffold returns `STATUS_NOT_SUPPORTED` unless a future lab build explicitly opts in with:

```text
GPUC_ENABLE_REPORTED_RESOURCE_READ
```

Do not define that flag until inventory IOCTLs are validated on a controlled test environment.

## Target

```text
ACPI\APP000B
Compatible ID: gpuc
```

## Files

- `gpuc-readonly.inf`: draft INF for review only.
- `gpuc-readonly.vcxproj`: WDK project scaffold.
- `gpuc-readonly.vcxproj.filters`: Visual Studio filter layout.
- `build-driver.ps1`: guarded build/check script.
- `driver.c`: KMDF entry and device setup skeleton.
- `queue.c`: read-only IOCTL dispatch skeleton.
- `gpuc-readonly.h`: internal driver definitions.
- `..\..\shared\gpuc-ioctl.h`: shared IOCTL contract.

## Build Status

The project is build-only. The script does not install, sign, create a service, enable Test Mode, or load a driver.

Check local prerequisites:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\driver\gpuc-readonly\build-driver.ps1 -CheckOnly
```

Attempt a local WDK build only after the check passes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\driver\gpuc-readonly\build-driver.ps1 -Configuration Release
```

If the WDK driver targets are missing, install the matching WDK/Visual Studio driver workload and rerun `-CheckOnly`.

Current known prerequisite shape on the first lab machine:

```text
MSBuild: present
Windows SDK 10.0.26100.0 user-mode headers/libs: present
VS driver platform toolsets: present after installing Windows Driver Kit component
WDK kernel headers/libs: not present
```

That means the scaffold can be reviewed, but the driver cannot be compiled on that machine until the standalone WDK kit payload is installed. The Visual Studio component can add project/toolset integration without placing `wdf.h` and `WdfDriverEntry.lib` under the Windows Kits tree.

Known missing payload evidence:

```text
wdf.h
WdfDriverEntry.lib
Windows Kits\10\Include\<version>\km
Windows Kits\10\Lib\<version>\km\x64
```

## Install Status

Do not install this on the main Windows environment.

Before any install experiment:

1. use a controlled test environment,
2. verify the original `APP000B` driver package is exported privately,
3. verify Safe Mode/WinRE access,
4. verify rollback commands,
5. confirm anti-cheat/Test Mode tradeoffs are acceptable.
