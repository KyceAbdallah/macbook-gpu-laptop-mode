param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceInstanceId,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedOriginalInf,

    [Parameter(Mandatory = $true)]
    [string]$OriginalDriverExport,

    [Parameter(Mandatory = $true)]
    [string]$ExperimentalInf
)

$ErrorActionPreference = "Stop"

function Write-Check {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Detail
    )

    $status = if ($Pass) { "PASS" } else { "FAIL" }
    Write-Output ("[{0}] {1}: {2}" -f $status, $Name, $Detail)
}

$failed = $false

$device = Get-PnpDevice -InstanceId $DeviceInstanceId -ErrorAction SilentlyContinue
Write-Check "Target device present" ($null -ne $device) $DeviceInstanceId
if ($null -eq $device) {
    exit 2
}

Write-Check "Target device status" ($device.Status -eq "OK") ("Status=" + $device.Status)
if ($device.Status -ne "OK") {
    $failed = $true
}

$props = Get-PnpDeviceProperty -InstanceId $DeviceInstanceId -ErrorAction Stop
$propMap = @{}
foreach ($prop in $props) {
    $propMap[$prop.KeyName] = $prop.Data
}

$currentInf = [string]$propMap["DEVPKEY_Device_DriverInfPath"]
$installSection = [string]$propMap["DEVPKEY_Device_DriverInfSection"]
$provider = [string]$propMap["DEVPKEY_Device_DriverProvider"]
$problemCode = [string]$propMap["DEVPKEY_Device_ProblemCode"]

Write-Output ""
Write-Output "Current binding:"
Write-Output ("  DriverInfPath: " + $currentInf)
Write-Output ("  DriverInfSection: " + $installSection)
Write-Output ("  DriverProvider: " + $provider)
Write-Output ("  ProblemCode: " + $problemCode)

$infMatches = ($currentInf -ieq $ExpectedOriginalInf)
Write-Check "Current INF matches expected original" $infMatches ("Current=" + $currentInf + "; Expected=" + $ExpectedOriginalInf)
if (-not $infMatches) {
    $failed = $true
}

$exportExists = Test-Path $OriginalDriverExport
$exportInf = if ($exportExists) { Get-ChildItem -Path $OriginalDriverExport -Filter *.inf -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
$exportCat = if ($exportExists) { Get-ChildItem -Path $OriginalDriverExport -Filter *.cat -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }

Write-Check "Original export folder exists" $exportExists $OriginalDriverExport
Write-Check "Original export contains INF" ($null -ne $exportInf) $(if ($exportInf) { $exportInf.FullName } else { "missing" })
Write-Check "Original export contains catalog" ($null -ne $exportCat) $(if ($exportCat) { $exportCat.FullName } else { "missing" })
if (-not $exportExists -or $null -eq $exportInf -or $null -eq $exportCat) {
    $failed = $true
}

$experimentalExists = Test-Path $ExperimentalInf
Write-Check "Experimental INF exists" $experimentalExists $ExperimentalInf
if (-not $experimentalExists) {
    $failed = $true
} else {
    $experimentalText = Get-Content -LiteralPath $ExperimentalInf -Raw
    Write-Output ""
    Write-Output "Experimental INF review hints:"
    Write-Output ("  Contains ACPI\APP000B: " + ($experimentalText -match [regex]::Escape("ACPI\APP000B")))
    Write-Output ("  Contains KmdfLibraryVersion: " + ($experimentalText -match "KmdfLibraryVersion"))
    Write-Output ("  Contains ServiceType=1: " + ($experimentalText -match "ServiceType\s*=\s*1"))
    Write-Output ("  Contains StartType=3: " + ($experimentalText -match "StartType\s*=\s*3"))
}

Write-Output ""
Write-Output "Non-mutating rollback dry-run:"
Write-Output ("  pnputil /delete-driver <experimental-oemXX.inf> /uninstall")
Write-Output ("  pnputil /add-driver `"{0}\*.inf`" /install" -f $OriginalDriverExport)

if ($failed) {
    Write-Output ""
    Write-Output "Preinstall review failed. Do not install or bind an experimental package."
    exit 2
}

Write-Output ""
Write-Output "Preinstall review passed for the checks this script can verify. Manual Safe Mode, encryption key, external display, and anti-cheat/Test Mode decisions are still required."
