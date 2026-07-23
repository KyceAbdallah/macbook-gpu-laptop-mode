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
