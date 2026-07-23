param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\captures\state"),
    [switch]$Redact
)

$ErrorActionPreference = "Continue"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $OutputDirectory $stamp
New-Item -ItemType Directory -Force -Path $out | Out-Null

$reportPath = Join-Path $out "state-summary.md"

function Add-Line {
    param([string]$Text = "")
    Add-Content -Path $reportPath -Value $Text -Encoding UTF8
}

function Format-HexAddress {
    param([UInt64]$Value)
    return "0x{0:X8}" -f $Value
}

function Redact-DeviceId {
    param([string]$Value)
    if (-not $Redact -or [string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    return ($Value -replace '\\[^\\]+$', '\<redacted-instance>')
}

function Redact-Path {
    param([string]$Value)
    if (-not $Redact -or [string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    return ($Value -replace '^.:\\Users\\[^\\]+', '<user-profile>')
}

function Get-VideoOutputTechnologyName {
    param([UInt32]$Value)

    switch ($Value) {
        0 { return "Other" }
        1 { return "HD15" }
        2 { return "SVideo" }
        3 { return "CompositeVideo" }
        4 { return "ComponentVideo" }
        5 { return "DVI" }
        6 { return "HDMI" }
        8 { return "D_JPN" }
        9 { return "SDI" }
        10 { return "DisplayPortExternal" }
        11 { return "DisplayPortEmbedded" }
        12 { return "UDIExternal" }
        13 { return "UDIEmbedded" }
        14 { return "SDTVDongle" }
        15 { return "Miracast" }
        16 { return "IndirectWired" }
        2147483648 { return "Internal" }
        4294967295 { return "Uninitialized" }
        default { return "Unknown($Value)" }
    }
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

        $path = $sample.Path
        if ($path -notmatch 'pid_([0-9]+)') {
            continue
        }

        $processId = [int]$Matches[1]
        if (-not $byPid.ContainsKey($processId)) {
            $processName = "unknown"
            try {
                $processName = (Get-Process -Id $processId -ErrorAction Stop).ProcessName
            }
            catch {}

            $byPid[$processId] = [pscustomobject]@{
                Pid = $processId
                ProcessName = $processName
                Utilization = 0.0
                Engines = New-Object System.Collections.Generic.HashSet[string]
            }
        }

        $byPid[$processId].Utilization += [double]$sample.CookedValue
        if ($path -match 'engtype_([^_\\)]+)') {
            [void]$byPid[$processId].Engines.Add($Matches[1])
        }
    }

    return @($byPid.Values | Sort-Object Utilization -Descending | Select-Object -First 12)
}

"# GPU Laptop Mode State" | Set-Content -Path $reportPath -Encoding UTF8
Add-Line
Add-Line ("Timestamp: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"))
Add-Line

$computer = Get-CimInstance Win32_ComputerSystem
Add-Line "## Computer"
Add-Line
Add-Line ("- Manufacturer: " + $computer.Manufacturer)
Add-Line ("- Model: " + $computer.Model)
Add-Line ("- SystemType: " + $computer.SystemType)
Add-Line

$video = Get-CimInstance Win32_VideoController |
    Select-Object Name,PNPDeviceID,DriverVersion,DriverDate,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate,Status

Add-Line "## Video Controllers"
Add-Line
foreach ($adapter in $video) {
    $activeMode = if ($adapter.CurrentHorizontalResolution -and $adapter.CurrentVerticalResolution) {
        "$($adapter.CurrentHorizontalResolution)x$($adapter.CurrentVerticalResolution)@$($adapter.CurrentRefreshRate)"
    }
    else {
        "none"
    }

    Add-Line ("- " + $adapter.Name)
    Add-Line ("  - Status: " + $adapter.Status)
    Add-Line ("  - DriverVersion: " + $adapter.DriverVersion)
    Add-Line ("  - ActiveMode: " + $activeMode)
    Add-Line ("  - PNPDeviceID: " + (Redact-DeviceId $adapter.PNPDeviceID))
}
Add-Line

$activeAdapters = @($video | Where-Object { $_.CurrentHorizontalResolution -and $_.CurrentVerticalResolution })
$panelOwner = if ($activeAdapters.Count -eq 1) {
    $activeAdapters[0].Name
}
elseif ($activeAdapters.Count -gt 1) {
    ($activeAdapters.Name -join ", ")
}
else {
    "unknown"
}

Add-Line "## Inferred Panel/Desktop Owner"
Add-Line
Add-Line ("- Active owner inference: " + $panelOwner)
Add-Line "- Inference basis: Win32_VideoController current resolution fields"
Add-Line

Add-Line "## Display Topology"
Add-Line
$monitors = @(Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue)
if ($monitors.Count -gt 0) {
    foreach ($monitor in $monitors) {
        Add-Line ("- " + $monitor.FriendlyName)
        Add-Line ("  - Status: " + $monitor.Status)
        Add-Line ("  - InstanceId: " + (Redact-DeviceId $monitor.InstanceId))
    }
}
else {
    Add-Line "- No monitor PnP devices found"
}

$connections = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue)
if ($connections.Count -gt 0) {
    Add-Line
    Add-Line "Connection params:"
    foreach ($connection in $connections) {
        Add-Line ("- " + (Redact-DeviceId $connection.InstanceName))
        Add-Line ("  - VideoOutputTechnology: " + (Get-VideoOutputTechnologyName ([uint32]$connection.VideoOutputTechnology)))
    }
}
Add-Line

Add-Line "## Battery and AC"
Add-Line
$batteries = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
$acAdapters = @(Get-PnpDevice | Where-Object { $_.InstanceId -like "ACPI\ACPI0003\*" -or $_.FriendlyName -eq "Microsoft AC Adapter" })
if ($batteries.Count -gt 0) {
    foreach ($battery in $batteries) {
        $batteryName = if ($Redact) { "<redacted-battery-name>" } else { $battery.Name }
        Add-Line ("- Battery: " + $batteryName)
        Add-Line ("  - EstimatedChargeRemaining: " + $battery.EstimatedChargeRemaining)
        Add-Line ("  - BatteryStatus: " + $battery.BatteryStatus)
        Add-Line ("  - Status: " + $battery.Status)
    }
}
else {
    Add-Line "- Battery: not found"
}
if ($acAdapters.Count -gt 0) {
    foreach ($adapter in $acAdapters) {
        Add-Line ("- AC Adapter: " + $adapter.Status)
    }
}
else {
    Add-Line "- AC Adapter: not found"
}
Add-Line

$gpuc = Get-PnpDevice |
    Where-Object { $_.InstanceId -like "ACPI\APP000B\*" -or $_.FriendlyName -eq "Apple graphics mux" } |
    Select-Object -First 1

Add-Line "## Apple Graphics Mux"
Add-Line
if ($gpuc) {
    Add-Line ("- InstanceId: " + (Redact-DeviceId $gpuc.InstanceId))
    Add-Line ("- Status: " + $gpuc.Status)
    Add-Line ("- Class: " + $gpuc.Class)
    Add-Line ("- FriendlyName: " + $gpuc.FriendlyName)

    $props = @{}
    Get-PnpDeviceProperty -InstanceId $gpuc.InstanceId -ErrorAction SilentlyContinue |
        ForEach-Object { $props[$_.KeyName] = $_.Data }

    foreach ($key in @(
        "DEVPKEY_Device_DriverInfPath",
        "DEVPKEY_Device_DriverInfSection",
        "DEVPKEY_Device_MatchingDeviceId",
        "DEVPKEY_Device_BiosDeviceName",
        "DEVPKEY_Device_Stack"
    )) {
        if ($props.ContainsKey($key)) {
            $value = $props[$key]
            if ($value -is [array]) {
                $value = $value -join ", "
            }
            Add-Line ("- " + $key + ": " + $value)
        }
    }

    $resources = Get-CimInstance Win32_PnPAllocatedResource |
        Where-Object { $_.Dependent -like "*APP000B*" -or $_.Antecedent -like "*APP000B*" }

    foreach ($resource in $resources) {
        if ($resource.Antecedent -match 'Win32_DeviceMemoryAddress \(StartingAddress = ([0-9]+)\)') {
            $start = [uint64]$Matches[1]
            $memory = Get-CimInstance Win32_DeviceMemoryAddress |
                Where-Object { $_.StartingAddress -eq $start } |
                Select-Object -First 1
            if ($memory) {
                Add-Line ("- MemoryResource: " + (Format-HexAddress $memory.StartingAddress) + "-" + (Format-HexAddress $memory.EndingAddress))
            }
        }
    }
}
else {
    Add-Line "- Not found"
}
Add-Line

$gpuPrefs = Get-ItemProperty -Path "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" -ErrorAction SilentlyContinue
Add-Line "## Per-App GPU Preferences"
Add-Line
if ($gpuPrefs) {
    $entries = @($gpuPrefs.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" })
    if ($Redact) {
        Add-Line ("- EntryCount: " + $entries.Count)
    }
    else {
        $entries | ForEach-Object {
            Add-Line ("- " + (Redact-Path $_.Name) + ": " + $_.Value)
        }
    }
}
else {
    Add-Line "- None found"
}

Add-Line
Add-Line "## Active GPU Processes"
Add-Line
$gpuProcesses = @(Get-GpuEngineProcessSummary)
if ($gpuProcesses.Count -gt 0) {
    foreach ($entry in $gpuProcesses) {
        $pidText = if ($Redact) { "<redacted-pid>" } else { [string]$entry.Pid }
        $engines = @($entry.Engines) -join ", "
        Add-Line ("- " + $entry.ProcessName)
        Add-Line ("  - PID: " + $pidText)
        Add-Line ("  - UtilizationSample: {0:N2}" -f $entry.Utilization)
        Add-Line ("  - Engines: " + $engines)
    }
}
else {
    Add-Line "- No active GPU engine counters above threshold"
}

Write-Output $reportPath
