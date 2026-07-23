param(
    [ValidateSet("Plan", "Apply")]
    [string]$Mode = "Plan",

    [string[]]$PreferIntegratedFor = @(),

    [string[]]$PreferHighPerformanceFor = @(),

    [string[]]$RemovePreferenceFor = @(),

    [string]$ProfilePath,

    [switch]$ListPreferences,

    [switch]$BatterySaverPlan
)

$ErrorActionPreference = "Stop"
$gpuPrefPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

if ($ProfilePath) {
    $profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    if ($profile.preferIntegratedFor) {
        $PreferIntegratedFor += @($profile.preferIntegratedFor)
    }
    if ($profile.preferHighPerformanceFor) {
        $PreferHighPerformanceFor += @($profile.preferHighPerformanceFor)
    }
    if ($profile.removePreferenceFor) {
        $RemovePreferenceFor += @($profile.removePreferenceFor)
    }
    if ($profile.batterySaverPlan) {
        $BatterySaverPlan = $true
    }
}

function Get-AppGpuPreferences {
    $prefs = Get-ItemProperty -Path $gpuPrefPath -ErrorAction SilentlyContinue
    if (-not $prefs) {
        return @()
    }

    return @($prefs.PSObject.Properties |
        Where-Object { $_.Name -notlike "PS*" } |
        ForEach-Object {
            [pscustomobject]@{
                Path = $_.Name
                Value = $_.Value
            }
        })
}

function Backup-AppGpuPreferences {
    if ($Mode -ne "Apply") {
        return
    }

    $backupRoot = Join-Path $PSScriptRoot "..\captures\user-mode-orchestrator"
    $backupDir = Join-Path $backupRoot $stamp
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backupPath = Join-Path $backupDir "user-gpu-preferences-before.json"
    Get-AppGpuPreferences | ConvertTo-Json -Depth 4 | Set-Content -Path $backupPath -Encoding UTF8
    Write-Output ("Backup: " + (Resolve-Path $backupPath))
}

function Set-AppGpuPreference {
    param(
        [string]$ExecutablePath,
        [ValidateSet("Integrated", "HighPerformance")]
        [string]$Preference
    )

    $fullPath = [System.IO.Path]::GetFullPath($ExecutablePath)
    $value = if ($Preference -eq "Integrated") {
        "GpuPreference=1;"
    } else {
        "GpuPreference=2;"
    }

    if ($Mode -eq "Apply") {
        New-Item -Path $gpuPrefPath -Force | Out-Null
        New-ItemProperty -Path $gpuPrefPath -Name $fullPath -Value $value -PropertyType String -Force | Out-Null
        Write-Output ("APPLIED: {0} -> {1}" -f $fullPath, $value)
    } else {
        Write-Output ("PLAN: set {0} -> {1}" -f $fullPath, $value)
    }
}

function Remove-AppGpuPreference {
    param([string]$ExecutablePath)

    $fullPath = [System.IO.Path]::GetFullPath($ExecutablePath)

    if ($Mode -eq "Apply") {
        if (Test-Path $gpuPrefPath) {
            Remove-ItemProperty -Path $gpuPrefPath -Name $fullPath -ErrorAction SilentlyContinue
        }
        Write-Output ("APPLIED: removed preference for {0}" -f $fullPath)
    } else {
        Write-Output ("PLAN: remove preference for {0}" -f $fullPath)
    }
}

Write-Output "User-mode laptop mode orchestrator prototype"
Write-Output ("Mode: " + $Mode)
Write-Output "Scope: per-app GPU preference and power-policy planning only."
Write-Output "No driver binding, mux access, MMIO access, EC access, or display topology changes are performed."
if ($ProfilePath) {
    Write-Output ("Profile: " + (Resolve-Path $ProfilePath))
}
Write-Output ""

if ($ListPreferences) {
    $existing = @(Get-AppGpuPreferences)
    Write-Output "Existing per-app GPU preferences:"
    if ($existing.Count -eq 0) {
        Write-Output "  none"
    } else {
        foreach ($entry in $existing) {
            Write-Output ("  {0} -> {1}" -f $entry.Path, $entry.Value)
        }
    }
    Write-Output ""
}

$willMutateGpuPrefs = $Mode -eq "Apply" -and (
    $PreferIntegratedFor.Count -gt 0 -or
    $PreferHighPerformanceFor.Count -gt 0 -or
    $RemovePreferenceFor.Count -gt 0
)

if ($willMutateGpuPrefs) {
    Backup-AppGpuPreferences
}

foreach ($path in $PreferIntegratedFor) {
    Set-AppGpuPreference -ExecutablePath $path -Preference Integrated
}

foreach ($path in $PreferHighPerformanceFor) {
    Set-AppGpuPreference -ExecutablePath $path -Preference HighPerformance
}

foreach ($path in $RemovePreferenceFor) {
    Remove-AppGpuPreference -ExecutablePath $path
}

if ($BatterySaverPlan) {
    if ($Mode -eq "Apply") {
        powercfg /setactive SCHEME_MAX | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "powercfg failed while setting the power saver plan."
        }
        Write-Output "APPLIED: active power scheme set to Power saver."
    } else {
        Write-Output "PLAN: powercfg /setactive SCHEME_MAX"
    }
}

if ($PreferIntegratedFor.Count -eq 0 -and $PreferHighPerformanceFor.Count -eq 0 -and $RemovePreferenceFor.Count -eq 0 -and -not $BatterySaverPlan -and -not $ListPreferences) {
    Write-Output "No actions requested. Provide app paths or -BatterySaverPlan to produce an orchestration plan."
}

Write-Output ""
Write-Output "Note: Windows may require signing out/restarting the target app before a per-app GPU preference takes effect."
