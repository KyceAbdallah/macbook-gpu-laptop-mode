# GPUC KMDF Client Scaffold

User-mode companion scaffold for the future read-only KMDF probe.

It does not install or load the driver. It only opens the device interface if the driver already exists in a controlled test environment.

Default behavior should remain inventory-only. Any resource byte read must require an explicit command-line flag.

## Intended Future Commands

```powershell
gpuc-kmdf-client.exe --version
gpuc-kmdf-client.exe --resources
```

Later, after inventory IOCTLs are validated in a controlled test environment:

```powershell
gpuc-kmdf-client.exe --read-reported-resource --index 0 --offset 0 --length 8
```

No resource byte read command or expanded 16-byte read command is implemented in phase 1.

## Build

This builds only the user-mode client. It does not build, install, sign, or load the KMDF driver.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\native\gpuc-kmdf-client\build.ps1
```
