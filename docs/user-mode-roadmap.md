# User-Mode Roadmap

## Milestone 1: Current State Summary

Produce a compact Markdown summary:

- computer model,
- display adapters,
- active display owner inference,
- Apple graphics mux binding,
- mux resource range if exposed by PnP,
- per-app GPU preference count.

## Milestone 2: Public-Safe Report Mode

Add a redacted report mode that removes:

- usernames,
- full device instance paths,
- full application paths,
- raw registry data.

## Milestone 3: Display Topology

Inspect monitor/display relationships:

- internal panel,
- external displays,
- active resolution and refresh rate,
- which adapter owns active modes.

## Milestone 4: Power State Observation

Observe only:

- AC vs battery,
- dGPU idle/load hints,
- whether the dGPU appears to power down,
- no power setting writes.

## Milestone 5: Native Inspector

Build a native user-mode inspector using SetupAPI and Configuration Manager APIs for more precise resource reporting than PowerShell/CIM.

## Milestone 6: User-Mode Capability Audit

Determine whether Windows exposes enough control to move the internal panel and DWM to the integrated GPU without a kernel driver.

The audit should confirm:

- active adapter ownership,
- display devices and monitors,
- `APP000B` binding state,
- per-app GPU preference availability,
- active GPU process hints,
- whether any user-mode mux command surface is visible.

Current expectation:

User mode can inspect and orchestrate Windows settings, but it probably cannot change mux routing or internal-panel ownership unless Apple exposes a separate user-accessible control surface.

## Milestone 7: User-Mode Orchestrator Prototype

Build a reversible prototype that only uses Windows-exposed user settings:

- per-app integrated GPU preference,
- per-app high-performance GPU preference,
- per-app GPU preference listing,
- per-app GPU preference removal,
- automatic preference backup before apply-mode registry writes,
- JSON profile input for repeatable plans,
- optional power-plan selection,
- no driver install,
- no Test Mode,
- no mux, EC, or MMIO access,
- no display topology mutation.

## Milestone 8: dGPU Wake Monitoring

Add a read-only watcher for GPU Engine performance counters so laptop-mode tuning can identify which applications keep GPU engines active.

The watcher should:

- sample active GPU Engine counters,
- group by process and engine type,
- write Markdown and CSV output,
- avoid registry, driver, mux, EC, MMIO, and display changes.
