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

Write-Output $reportPath
