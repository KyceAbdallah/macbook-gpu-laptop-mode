# Status Checklist

Updated: 2026-07-23 01:04:05 -04:00

## Completed

- [x] Created public repo for sanitized research, docs, and reusable tooling.
- [x] Kept raw captures, machine-specific IDs, registry exports, and private logs out of the public repo.
- [x] Added public-safe GPU laptop-mode architecture notes.
- [x] Added public safety notes and recovery checklist.
- [x] Added a PowerShell state reporter for desktop owner, adapter state, `GPUC`, topology, battery/AC, GPU process hints, and per-app GPU preferences.
- [x] Documented that Windows desktop ownership is currently not a simple DWM setting.
- [x] Documented that the likely missing piece is Apple mux control plus Intel panel ownership, not Project Falcon alone.
- [x] Added a no-write native user-mode `GPUC` inspector using SetupAPI/Configuration Manager plus WMI fallback.
- [x] Documented the `APP000B` / Apple gmux interpretation.
- [x] Added public design docs for a read-only KMDF probe.
- [x] Added a shared read-only IOCTL contract.
- [x] Added a user-mode client scaffold for a future installed KMDF probe.
- [x] Added a guarded WDK build scaffold.
- [x] Built the KMDF scaffold successfully in compile-only mode.
- [x] Hardened the KMDF scaffold with an administrator/System-only device interface ACL.
- [x] Kept `IOCTL_GPUC_READ_RESOURCE_BYTES` disabled by default unless a future build explicitly defines `GPUC_ENABLE_REPORTED_RESOURCE_READ`.
- [x] Added a non-mutating preinstall checker.
- [x] Added a rollback helper that dry-runs unless `-Execute` is supplied.
- [x] Added a signed test package plan.
- [x] Added a non-mutating package audit script.
- [x] Verified the package audit passes without catalog generation, signing, staging, install, service creation, driver load, or binding.

## Current Verified Safety Boundary

- [x] No driver install.
- [x] No package staging.
- [x] No signing.
- [x] No Test Mode.
- [x] No service creation.
- [x] No driver load.
- [x] No mux writes.
- [x] No EC access.
- [x] No default MMIO mapping.
- [x] No default MMIO reads.
- [x] No display adapter enable/disable changes.
- [x] No display topology changes.

## Current Build Artifact

```text
driver/gpuc-readonly/x64/Release/gpuc-readonly.sys
Size: 16896 bytes
SHA256: A46F0CDCF65766A96AF2F1D5F1DC52D086AA7520C4C9A6C1BF7FB3CC438E1A53
```

The build artifact is local output only and is ignored by git.

## Needs To Be Done

- [ ] Make `audit-package.ps1` stricter by failing on forbidden compile flags such as `GPUC_ENABLE_REPORTED_RESOURCE_READ`.
- [ ] Make `audit-package.ps1` list the exact files allowed in any future package.
- [ ] Add a package manifest template that records INF/SYS/CAT hashes without committing generated binaries.
- [ ] Decide whether to allow catalog generation as a separate risk gate.
- [ ] If catalog generation is approved, generate only the catalog and record its hash; do not sign or install yet.
- [ ] Decide whether local test signing is acceptable given anti-cheat/Test Mode tradeoffs.
- [ ] If signing is approved, create a separate signing plan before touching `bcdedit`, certificates, or the driver store.
- [ ] Only after a fresh preinstall check and rollback dry-run, decide whether to stage/install on a controlled test path.
- [ ] After any future installed read-only probe, use the KMDF client to validate version/resources/counters only.
- [ ] Keep mux-control, EC writes, and MMIO reads/writes out of scope until inventory-only driver behavior is validated.
