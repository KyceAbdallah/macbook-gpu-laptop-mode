# MacBook GPU Laptop Mode Lab

Public research notes and user-mode tools for investigating Windows GPU switching on Intel MacBook systems with Apple graphics mux hardware.

## Goal

Explore whether Windows can support a practical laptop mode where:

- the integrated GPU owns the internal display and desktop composition,
- the discrete GPU remains available for high-performance rendering when possible,
- power behavior is observable and reversible,
- risky driver work is deferred until user-mode evidence supports it.

## Current Direction

This project starts in user mode:

- enumerate display adapters,
- identify the current desktop/panel owner,
- inspect Apple graphics mux PnP binding,
- record public-safe summaries,
- avoid kernel drivers, mux writes, and registry mutation until the platform behavior is understood.

## Current Artifacts

- `scripts/get-gpu-laptop-mode-state.ps1`: public-safe PowerShell state reporter.
- `native/gpuc-inspector/`: no-write native user-mode inspector.
- `driver/gpuc-readonly/`: review-only KMDF source scaffold.
- `native/gpuc-kmdf-client/`: user-mode client scaffold for a future installed probe.
- `shared/gpuc-ioctl.h`: shared read-only IOCTL contract.

## Privacy Model

Do not commit local captures. Diagnostic output can contain machine names, device instance IDs, driver inventory, registry data, and other fingerprints.

This public repo intentionally excludes:

- DxDiag captures,
- registry exports,
- raw ACPI dumps from a personal machine,
- Discord webhook configuration,
- private build/test logs.

## Safety

The scripts in this repo are intended to be read-only. They should not change display state, drivers, registry values, or firmware/mux state.

Before any future kernel or mux-control work, use a private lab repo and document recovery paths first.
