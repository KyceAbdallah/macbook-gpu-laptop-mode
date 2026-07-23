# Read-Only KMDF Probe Design

## Goal

Design a first kernel component that observes Apple graphics mux state without changing display, mux, EC, registry, driver, or power state.

This is a design document only. Do not build, install, or test-sign this driver on the main Windows install yet.

## Scope

The probe should:

- bind to the Apple graphics mux ACPI device (`APP000B`),
- report the device identity and translated resources Windows assigns,
- expose a private read-only device interface,
- provide explicit IOCTLs for inventory and byte reads,
- refuse all writes or control operations,
- make failure boring: no retries that could spam ACPI, no background polling by default.

The probe should not:

- switch GPUs,
- write mux or EC state,
- enable or disable adapters,
- change display topology,
- install or modify display drivers,
- write registry GPU preferences,
- attempt Optimus-style or Dynamic Switchable Graphics policy changes.

## Binding Model

Target hardware ID:

```text
ACPI\APP000B
```

Expected compatible ID:

```text
gpuc
```

The current Windows binding may be a null-function driver. The read-only probe would replace that binding only in a controlled test environment, and only after a full restore plan exists.

Driver shape:

```text
KMDF PnP function/filter driver: yes, likely function driver for APP000B in a test environment
Device interface: yes, private lab GUID
User-mode companion: yes, opens interface and calls read-only IOCTLs
```

## Resource Handling

On `EvtDevicePrepareHardware`, enumerate raw and translated resources.

For each memory resource:

- record physical start,
- record length,
- record translated address,
- record flags,
- validate expected size before mapping.

The current public hypothesis is that this class of Apple mux exposes a tiny MMIO resource whose base is sufficient to identify a T2-style gmux window. Linux-derived behavior indicates the MMIO command protocol may use offsets beyond an 8-byte ACPI-declared allocation, so the first Windows probe should only use the resource length Windows reports.

Initial policy:

```text
Map only the exact Windows-reported resource length.
Read only.
No speculative 16-byte mapping in phase 1.
```

An expanded 16-byte read can be designed later as a separate opt-in experiment if the private evidence supports it.

## IOCTL Contract

Use buffered IOCTLs with fixed-size versioned structs.

```text
IOCTL_GPUC_GET_VERSION
IOCTL_GPUC_GET_DEVICE_INFO
IOCTL_GPUC_GET_RESOURCES
IOCTL_GPUC_READ_RESOURCE_BYTES
IOCTL_GPUC_GET_NOTIFICATION_COUNTERS
IOCTL_GPUC_GET_LAST_ERROR_STATE
```

`IOCTL_GPUC_READ_RESOURCE_BYTES` should accept:

```text
struct GPUC_READ_REQUEST {
    UINT32 Version;
    UINT32 ResourceIndex;
    UINT32 Offset;
    UINT32 Length;
};
```

Validation:

- `Offset + Length` must fit inside the reported resource length.
- maximum read length should be small, for example 256 bytes.
- zero-length reads are rejected.
- writes are not implemented.

## User-Mode Companion

The user-mode tool should:

- enumerate the private interface,
- print driver version,
- print PnP identity,
- print raw and translated resources,
- optionally perform one bounded read of the reported resource,
- save Markdown and JSON reports.

The tool should require an explicit flag before any MMIO byte read:

```text
gpuc-kmdf-client.exe --read-reported-resource
```

Default run should inventory only.

## Failure Rules

Return an error and avoid further action when:

- no memory resource is present,
- multiple ambiguous mux memory resources are present,
- translated resource length is shorter than expected,
- mapping fails,
- the device is not `APP000B`,
- user-mode asks to read outside the reported resource.

Log using WPP/ETW, but keep logs free of secrets and webhook values.

## Test Environment

Before any driver build/install work:

- create a restore point or full image,
- confirm remote recovery path,
- confirm BitLocker/recovery key state if applicable,
- use a non-gaming or disposable Windows install where Test Mode and anti-cheat conflicts are acceptable,
- export the original driver binding for `APP000B`,
- document rollback commands.

## Phase Gates

1. Finish user-mode evidence.
2. Write KMDF skeleton, uninstalled.
3. Build in WDK, uninstalled.
4. Review INF and rollback plan.
5. Install only on a controlled test environment.
6. Run inventory-only IOCTLs.
7. Consider a bounded read of the reported resource.

## Scaffold Status

The public repo now contains a source scaffold only:

```text
shared/gpuc-ioctl.h
driver/gpuc-readonly/
native/gpuc-kmdf-client/
```

Current scaffold boundaries:

- the INF is review-only,
- no WDK project is provided yet,
- no install script is provided,
- the user-mode client can be built independently,
- the client reports a missing interface until a driver is intentionally installed in a controlled test environment,
- no expanded 16-byte read command exists.

The user-mode client build validates the shared IOCTL header, but does not validate the KMDF driver build.
