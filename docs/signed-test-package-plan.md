# Signed Test Package Plan

This document describes the next possible packaging step for the `gpuc-readonly` KMDF scaffold.

It is a plan only. It does not approve installing, staging, signing, enabling Test Mode, loading the driver, or binding it to `ACPI\APP000B`.

## Current Package Intent

The experimental package is meant to bind only to:

```text
ACPI\APP000B
```

Current intended behavior:

- demand-start kernel service,
- KMDF 1.15,
- administrator/System-only device interface ACL,
- inventory IOCTLs only,
- no write IOCTLs,
- no default MMIO mapping,
- no default MMIO reads,
- no EC access,
- no display adapter state changes.

## Package Contents

Expected package inputs:

```text
driver/gpuc-readonly/gpuc-readonly.inf
driver/gpuc-readonly/x64/Release/gpuc-readonly.sys
```

Generated later, only after explicit approval:

```text
gpuc-readonly.cat
```

The `.pdb`, `.obj`, `.lib`, `.tlog`, and other build intermediate files are not part of an install package.

## Local Validation Gates

Before signing:

1. Build with `build-driver.ps1`.
2. Record `.sys` size and SHA256.
3. Run the preinstall checker.
4. Run the rollback helper in dry-run mode.
5. Confirm Safe Mode/WinRE recovery.
6. Confirm encryption recovery-key availability if applicable.
7. Confirm anti-cheat/Test Mode tradeoff.
8. Confirm the user explicitly approves catalog generation/signing.

Before install:

1. Confirm the signed package hash.
2. Confirm the original driver export still exists.
3. Confirm the target device is still healthy.
4. Confirm the current binding still matches the expected original driver.
5. Confirm rollback commands are copied into the private log.
6. Confirm the user explicitly approves staging/install.

## Signing Options

Option A: Test-sign locally.

- Requires a local test certificate.
- Usually requires Test Mode for kernel driver loading.
- May block games or software with strict anti-cheat policies.
- Best for isolated testing, not daily-driver gaming.

Option B: Attestation or production signing.

- Avoids Test Mode, but requires the Microsoft driver signing pipeline.
- More work and not appropriate until the read-only probe proves useful.

Option C: Do not sign yet.

- Current safest option.
- Continue source review, package audit, and user-mode probing.

## Current Recommendation

Stay at Option C until the user explicitly accepts the next risk gate.

The next concrete step is package audit only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\driver\gpuc-readonly\audit-package.ps1
```

That script does not sign, stage, install, load, or bind the driver.
