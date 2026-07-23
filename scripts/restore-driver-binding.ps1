param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceInstanceId,

    [Parameter(Mandatory = $true)]
    [string]$OriginalDriverExport,

    [string]$ExperimentalPublishedInf,

    [switch]$Execute
)

$ErrorActionPreference = "Stop"

function Invoke-Or-Print {
    param(
        [string]$Label,
        [string]$Command,
        [scriptblock]$Action
    )

    if ($Execute) {
        Write-Output ("EXECUTE: " + $Label)
        & $Action
        if ($LASTEXITCODE -ne 0) {
            throw ("Command failed: " + $Command)
        }
    } else {
        Write-Output ("DRY-RUN: " + $Command)
    }
}

$device = Get-PnpDevice -InstanceId $DeviceInstanceId -ErrorAction SilentlyContinue
if ($null -eq $device) {
    throw ("Target device not found: " + $DeviceInstanceId)
}

$originalInf = Get-ChildItem -Path $OriginalDriverExport -Filter *.inf -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $originalInf) {
    throw ("Original driver export does not contain an INF: " + $OriginalDriverExport)
}

Write-Output ("TargetDevice: " + $DeviceInstanceId)
Write-Output ("CurrentStatus: " + $device.Status)
Write-Output ("OriginalInf: " + $originalInf.FullName)
Write-Output ("Mode: " + $(if ($Execute) { "EXECUTE" } else { "DRY-RUN" }))
Write-Output ""

if ($ExperimentalPublishedInf) {
    Invoke-Or-Print `
        -Label "Remove experimental driver package" `
        -Command ("pnputil /delete-driver {0} /uninstall" -f $ExperimentalPublishedInf) `
        -Action { pnputil /delete-driver $ExperimentalPublishedInf /uninstall }
}

Invoke-Or-Print `
    -Label "Reinstall exported original driver package" `
    -Command ("pnputil /add-driver `"{0}`" /install" -f $originalInf.FullName) `
    -Action { pnputil /add-driver $originalInf.FullName /install }

Write-Output ""
Write-Output "After execution, verify the target device binding and status with:"
Write-Output ("Get-PnpDevice -InstanceId '" + $DeviceInstanceId + "'")
Write-Output ("Get-PnpDeviceProperty -InstanceId '" + $DeviceInstanceId + "' | Sort-Object KeyName | Format-List KeyName,Data")
