# Pre-Install Package Review

This checklist must pass before any experimental package is installed or bound to `ACPI\APP000B`.

It is public-safe and intentionally avoids local instance IDs, exported package paths, registry exports, or machine-specific captures.

## Current Boundary

Allowed:

- compile-only driver build,
- INF/source review,
- package shape review,
- rollback script dry-runs,
- user-mode inventory tools.

Not allowed without a new explicit decision:

- enabling Test Mode,
- signing a package,
- staging a driver with `pnputil /add-driver`,
- binding an experimental driver with `/install`,
- creating or starting a service,
- loading the `.sys`,
- reading or writing mux/EC/MMIO registers,
- changing display adapter state.

## Package Review Checklist

1. Confirm the experimental INF matches only the intended ACPI hardware ID.
2. Confirm the current original driver package has been exported.
3. Confirm the rollback command uses the exported original package, not an internet download.
4. Confirm the target device is healthy before the experiment.
5. Confirm Safe Mode or Windows Recovery Environment access.
6. Confirm BitLocker or device encryption recovery-key availability.
7. Confirm external display availability if display routing might be affected.
8. Confirm the test package does not include write IOCTLs.
9. Confirm the test package does not map or read MMIO by default.
10. Confirm the device interface ACL is limited to LocalSystem and built-in Administrators.
11. Confirm the build is reproducible and the artifact hash is recorded.
12. Confirm no anti-cheat-sensitive state, such as Test Mode, will be enabled unless the user accepts that tradeoff.

## Dry-Run Commands

Run the public preinstall checker with explicit values:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-driver-preinstall.ps1 `
  -DeviceInstanceId '<device-instance-id>' `
  -ExpectedOriginalInf '<published-original-inf>' `
  -OriginalDriverExport '<path-to-exported-original-driver-folder>' `
  -ExperimentalInf '.\driver\gpuc-readonly\gpuc-readonly.inf'
```

Run rollback helper in dry-run mode first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\restore-driver-binding.ps1 `
  -DeviceInstanceId '<device-instance-id>' `
  -OriginalDriverExport '<path-to-exported-original-driver-folder>' `
  -ExperimentalPublishedInf '<experimental-oemXX.inf>'
```

The rollback helper prints commands by default. It does not mutate driver state unless `-Execute` is supplied.

## Proceed/Stop Rule

Proceed only when:

- the checker reports all required inputs present,
- the current target device status is OK,
- the original export folder contains an INF and catalog,
- the experimental INF review is acceptable,
- rollback commands have been dry-run and reviewed.

Stop if:

- the target device is missing or unhealthy,
- the original driver export is missing,
- the experimental INF matches a broader ID than intended,
- the build artifact hash is unknown,
- the user has not explicitly approved the next risk level.
