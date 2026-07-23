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
- `driver.c`: KMDF entry and device setup skeleton.
- `queue.c`: read-only IOCTL dispatch skeleton.
- `gpuc-readonly.h`: internal driver definitions.
- `..\..\shared\gpuc-ioctl.h`: shared IOCTL contract.

## Build Status

No build project is provided yet. Add the WDK project only after the INF and rollback path have been reviewed.

## Install Status

Do not install this on the main Windows environment.

Before any install experiment:

1. use a controlled test environment,
2. verify the original `APP000B` driver package is exported privately,
3. verify Safe Mode/WinRE access,
4. verify rollback commands,
5. confirm anti-cheat/Test Mode tradeoffs are acceptable.
