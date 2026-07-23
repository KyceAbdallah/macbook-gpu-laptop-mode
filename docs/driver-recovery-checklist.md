# Driver Recovery Checklist

## Purpose

Prepare rollback before any experimental driver binding, signing, or installation work.

This checklist is intentionally generic and public-safe. Exact device instance IDs, local captures, exported driver packages, and full driver inventories belong in a private lab repo.

## Required Before Driver Work

1. Record the target device instance ID.
2. Record the current hardware IDs and compatible IDs.
3. Record the current driver INF, provider, class, version, signer, and install section.
4. Export the currently bound driver package.
5. Capture the current display adapter state.
6. Capture the current display topology.
7. Confirm Safe Mode or Windows Recovery Environment access.
8. Confirm an external display path if display routing could be affected.
9. Confirm whether BitLocker or device encryption recovery keys are needed.
10. Write rollback commands before installing an experimental package.

## Capture Commands

Run from an elevated PowerShell prompt when possible:

```powershell
Get-PnpDevice -InstanceId '<device-instance-id>' | Format-List *
Get-PnpDeviceProperty -InstanceId '<device-instance-id>' | Sort-Object KeyName | Format-List KeyName,Type,Data
pnputil /enum-drivers /files
pnputil /export-driver <published-inf-name> <private-backup-folder>
```

For display state:

```powershell
Get-CimInstance Win32_VideoController
Get-PnpDevice -Class Display
Get-PnpDevice -Class Monitor
```

## Rollback Outline

If an experimental driver was installed and the device is still reachable:

```powershell
pnputil /delete-driver <experimental-inf-name> /uninstall
pnputil /add-driver <exported-original-inf-path> /install
```

If the system cannot boot normally:

1. Boot into Windows Recovery Environment.
2. Use Startup Settings to enter Safe Mode.
3. Remove the experimental driver package.
4. Reinstall the exported original package.
5. Reboot and verify the original binding.

## Verification

After rollback, verify:

- target device status is OK,
- target driver INF matches the original package,
- target install section matches the original section,
- display adapters are present,
- the internal panel is still reachable,
- no new ACPI or display-driver errors appeared immediately after boot.
