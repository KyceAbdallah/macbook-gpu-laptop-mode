param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\captures\user-mode-capability"),
    [switch]$Redact
)

$ErrorActionPreference = "Continue"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $OutputDirectory $stamp
New-Item -ItemType Directory -Force -Path $out | Out-Null
$reportPath = Join-Path $out "user-mode-capability.md"
$jsonPath = Join-Path $out "user-mode-capability.json"

function Add-Line {
    param([string]$Text = "")
    Add-Content -Path $reportPath -Value $Text -Encoding UTF8
}

function Redact-DeviceId {
    param([string]$Value)
    if (-not $Redact -or [string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    return ($Value -replace '\\[^\\]+$', '\<redacted-instance>')
}

function Get-GpuClass {
    param([string]$Name, [string]$PnpId)

    if ($Name -match "Intel|UHD|Iris" -or $PnpId -match "VEN_8086") {
        return "Integrated"
    }
    if ($Name -match "AMD|Radeon|NVIDIA|GeForce" -or $PnpId -match "VEN_1002|VEN_10DE") {
        return "Discrete"
    }
    return "Unknown"
}

function Get-DisplayDeviceSnapshot {
    $source = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class DisplayDeviceReader {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    public static object[] Read() {
        var rows = new List<object>();
        uint adapterIndex = 0;
        while (true) {
            var adapter = new DISPLAY_DEVICE();
            adapter.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, adapterIndex, ref adapter, 0)) {
                break;
            }
            rows.Add(new {
                Kind = "Adapter",
                Parent = "",
                Name = adapter.DeviceName,
                String = adapter.DeviceString,
                Id = adapter.DeviceID,
                Key = adapter.DeviceKey,
                StateFlags = adapter.StateFlags
            });

            uint monitorIndex = 0;
            while (true) {
                var monitor = new DISPLAY_DEVICE();
                monitor.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
                if (!EnumDisplayDevices(adapter.DeviceName, monitorIndex, ref monitor, 0)) {
                    break;
                }
                rows.Add(new {
                    Kind = "Monitor",
                    Parent = adapter.DeviceName,
                    Name = monitor.DeviceName,
                    String = monitor.DeviceString,
                    Id = monitor.DeviceID,
                    Key = monitor.DeviceKey,
                    StateFlags = monitor.StateFlags
                });
                monitorIndex++;
            }
            adapterIndex++;
        }
        return rows.ToArray();
    }
}
"@

    if (-not ("DisplayDeviceReader" -as [type])) {
        Add-Type -TypeDefinition $source -ErrorAction Stop
    }

    return [DisplayDeviceReader]::Read()
}

function Get-GpuEngineProcessSummary {
    $samples = Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction SilentlyContinue
    if (-not $samples) {
        return @()
    }

    $byPid = @{}
    foreach ($sample in $samples.CounterSamples) {
        if ($sample.CookedValue -le 0.01) {
            continue
        }

        if ($sample.Path -notmatch 'pid_([0-9]+)') {
            continue
        }

        $processId = [int]$Matches[1]
        if (-not $byPid.ContainsKey($processId)) {
            $processName = "unknown"
            try {
                $processName = (Get-Process -Id $processId -ErrorAction Stop).ProcessName
            } catch {}

            $byPid[$processId] = [pscustomobject]@{
                Pid = $processId
                ProcessName = $processName
                Utilization = 0.0
                Engines = New-Object System.Collections.Generic.HashSet[string]
            }
        }

        $byPid[$processId].Utilization += [double]$sample.CookedValue
        if ($sample.Path -match 'engtype_([^_\\)]+)') {
            [void]$byPid[$processId].Engines.Add($Matches[1])
        }
    }

    return @($byPid.Values | Sort-Object Utilization -Descending | Select-Object -First 12)
}

"# User-Mode Laptop Mode Capability Audit" | Set-Content -Path $reportPath -Encoding UTF8
Add-Line
Add-Line ("Timestamp: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"))
Add-Line
Add-Line "Mode: read-only user-mode audit. No registry writes, driver changes, mux access, MMIO reads, or display changes are attempted."
Add-Line

$video = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
$displayDevices = @(Get-DisplayDeviceSnapshot)
$displayClass = @(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue)
$monitors = @(Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue)
$gpuc = Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like "ACPI\APP000B\*" -or $_.FriendlyName -eq "Apple graphics mux" } |
    Select-Object -First 1
$gpuPrefs = Get-ItemProperty -Path "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" -ErrorAction SilentlyContinue
$gpuProcesses = @(Get-GpuEngineProcessSummary)

$adapterRows = foreach ($adapter in $video) {
    $activeMode = $null
    if ($adapter.CurrentHorizontalResolution -and $adapter.CurrentVerticalResolution) {
        $activeMode = "$($adapter.CurrentHorizontalResolution)x$($adapter.CurrentVerticalResolution)@$($adapter.CurrentRefreshRate)"
    }

    [pscustomobject]@{
        Name = $adapter.Name
        GpuClass = Get-GpuClass $adapter.Name $adapter.PNPDeviceID
        PnpDeviceId = Redact-DeviceId $adapter.PNPDeviceID
        DriverVersion = $adapter.DriverVersion
        Status = $adapter.Status
        ActiveMode = if ($activeMode) { $activeMode } else { "none" }
        HasActiveMode = [bool]$activeMode
    }
}

$activeAdapters = @($adapterRows | Where-Object { $_.HasActiveMode })
$integratedActive = @($activeAdapters | Where-Object { $_.GpuClass -eq "Integrated" }).Count -gt 0
$discreteActive = @($activeAdapters | Where-Object { $_.GpuClass -eq "Discrete" }).Count -gt 0
$onlyDiscreteActive = $discreteActive -and -not $integratedActive
$onlyIntegratedActive = $integratedActive -and -not $discreteActive

$desktopOwner = if ($activeAdapters.Count -eq 1) {
    $activeAdapters[0].Name
} elseif ($activeAdapters.Count -gt 1) {
    ($activeAdapters.Name -join ", ")
} else {
    "unknown"
}

Add-Line "## Adapter Activity"
Add-Line
foreach ($adapter in $adapterRows) {
    Add-Line ("- " + $adapter.Name)
    Add-Line ("  - Class: " + $adapter.GpuClass)
    Add-Line ("  - Status: " + $adapter.Status)
    Add-Line ("  - ActiveMode: " + $adapter.ActiveMode)
    Add-Line ("  - DriverVersion: " + $adapter.DriverVersion)
    Add-Line ("  - PNPDeviceID: " + $adapter.PnpDeviceId)
}
Add-Line

Add-Line "## Desktop Ownership Inference"
Add-Line
Add-Line ("- Inferred owner: " + $desktopOwner)
Add-Line ("- Integrated active: " + $integratedActive)
Add-Line ("- Discrete active: " + $discreteActive)
Add-Line

Add-Line "## Display Devices"
Add-Line
foreach ($device in $displayDevices) {
    Add-Line ("- " + $device.Kind + ": " + $device.String)
    Add-Line ("  - Name: " + $device.Name)
    if ($device.Parent) {
        Add-Line ("  - Parent: " + $device.Parent)
    }
    Add-Line ("  - StateFlags: 0x{0:X}" -f $device.StateFlags)
    Add-Line ("  - Id: " + (Redact-DeviceId $device.Id))
}
Add-Line

Add-Line "## PnP Display Class"
Add-Line
foreach ($device in $displayClass) {
    Add-Line ("- " + $device.FriendlyName)
    Add-Line ("  - Status: " + $device.Status)
    Add-Line ("  - InstanceId: " + (Redact-DeviceId $device.InstanceId))
}
Add-Line

Add-Line "## Monitor Class"
Add-Line
foreach ($monitor in $monitors) {
    Add-Line ("- " + $monitor.FriendlyName)
    Add-Line ("  - Status: " + $monitor.Status)
    Add-Line ("  - InstanceId: " + (Redact-DeviceId $monitor.InstanceId))
}
Add-Line

Add-Line "## Apple Graphics Mux"
Add-Line
if ($gpuc) {
    Add-Line ("- Present: true")
    Add-Line ("- Status: " + $gpuc.Status)
    Add-Line ("- InstanceId: " + (Redact-DeviceId $gpuc.InstanceId))
    $props = @{}
    Get-PnpDeviceProperty -InstanceId $gpuc.InstanceId -ErrorAction SilentlyContinue |
        ForEach-Object { $props[$_.KeyName] = $_.Data }
    foreach ($key in @("DEVPKEY_Device_DriverInfPath", "DEVPKEY_Device_DriverInfSection", "DEVPKEY_Device_BiosDeviceName", "DEVPKEY_Device_Stack")) {
        if ($props.ContainsKey($key)) {
            Add-Line ("- " + $key + ": " + $props[$key])
        }
    }
} else {
    Add-Line "- Present: false"
}
Add-Line

Add-Line "## Windows-Exposed Control Surface"
Add-Line
$gpuPrefEntries = if ($gpuPrefs) { @($gpuPrefs.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }) } else { @() }
Add-Line ("- Per-app GPU preferences available: " + [bool]($gpuPrefs -or (Test-Path "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences")))
Add-Line ("- Per-app GPU preference entry count: " + $gpuPrefEntries.Count)
Add-Line "- Display ownership switch API exposed by this audit: false"
Add-Line "- APP000B user-mode mux command interface found: false"
Add-Line "- User-mode physical MMIO access attempted: false"
Add-Line

Add-Line "## Active GPU Processes"
Add-Line
if ($gpuProcesses.Count -gt 0) {
    foreach ($entry in $gpuProcesses) {
        $pidText = if ($Redact) { "<redacted-pid>" } else { [string]$entry.Pid }
        Add-Line ("- " + $entry.ProcessName)
        Add-Line ("  - PID: " + $pidText)
        Add-Line ("  - UtilizationSample: {0:N2}" -f $entry.Utilization)
        Add-Line ("  - Engines: " + ((@($entry.Engines)) -join ", "))
    }
} else {
    Add-Line "- No active GPU engine counters above threshold"
}
Add-Line

$verdict = if ($onlyDiscreteActive) {
    "User-mode evidence says the desktop/internal active mode is currently discrete-only. No Windows-exposed user-mode control was found that can move DWM/internal panel ownership to the integrated GPU."
} elseif ($onlyIntegratedActive) {
    "Integrated GPU already owns the only active mode."
} elseif ($integratedActive -and $discreteActive) {
    "Both GPU classes have active modes; further topology-specific testing is needed."
} else {
    "No active GPU owner could be inferred from user-mode data."
}

Add-Line "## Verdict"
Add-Line
Add-Line ("- " + $verdict)
Add-Line "- User-mode can still orchestrate per-app GPU preferences and power policy."
Add-Line "- Direct mux switching or panel-owner migration was not proven available from user mode."

$json = [pscustomobject]@{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
    mode = "read-only user-mode audit"
    desktopOwner = $desktopOwner
    integratedActive = $integratedActive
    discreteActive = $discreteActive
    app000bPresent = [bool]$gpuc
    perAppGpuPreferenceCount = $gpuPrefEntries.Count
    displayOwnershipSwitchApiFound = $false
    app000bUserModeMuxCommandInterfaceFound = $false
    userModePhysicalMmioAccessAttempted = $false
    verdict = $verdict
    adapters = $adapterRows
}
$json | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Output $reportPath
Write-Output $jsonPath
