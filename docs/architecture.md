# Architecture

## Working Hypothesis

On affected Intel MacBook systems, Windows can see both GPUs, but the internal panel is owned by whichever GPU the platform mux routes to the panel. Desktop Window Manager follows the active display path; it is not the primary control point.

The likely layers are:

1. Apple platform mux / ACPI device.
2. Integrated and discrete display drivers.
3. Windows display topology and VidPN paths.
4. DWM composition on the active display owner.
5. Per-application GPU preference for render workloads.

## User-Mode First

The first phase avoids custom kernel code:

- PnP inspection with PowerShell/CIM.
- Display adapter state inspection.
- ACPI table analysis performed offline.
- No direct physical memory access.
- No embedded controller writes.
- No mux switching.

## Later Driver Track

A future read-only KMDF driver may be useful if user-mode APIs cannot observe the mux state.

Initial driver constraints:

- bind only to the Apple graphics mux ACPI device,
- map reported resources read-only where possible,
- expose read-only IOCTLs,
- never write mux registers in the first milestone.
