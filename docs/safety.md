# Safety Notes

## Avoid First

- Do not disable the active display adapter while the internal panel depends on it.
- Do not force-install display drivers without a recovery plan.
- Do not write to mux, EC, or MMIO resources from an exploratory tool.
- Do not enable Windows Test Mode on a gaming install unless you understand anti-cheat impact.

## Anti-Cheat Considerations

Plain user-mode tools do not require Windows Test Mode.

Custom kernel drivers usually require a proper signing path. During development, test-signed drivers often require Test Mode, and many anti-cheat systems block or distrust Test Mode, unsigned drivers, debug boot settings, or unknown kernel components.

Preferred order:

1. user-mode diagnostics,
2. private read-only driver design,
3. WDK build in a controlled test environment,
4. signed production-style driver only if the approach proves viable.

## Public Data Hygiene

Do not publish raw captures by default. Treat these as potentially sensitive:

- `dxdiag.txt`,
- registry exports,
- PnP instance IDs,
- full driver inventories,
- ACPI dumps tied to a specific personal machine,
- logs containing usernames or installed application paths.
