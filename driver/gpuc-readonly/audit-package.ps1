param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [switch]$GenerateCatalog
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$inf = Join-Path $root "gpuc-readonly.inf"
$project = Join-Path $root "gpuc-readonly.vcxproj"
$buildScript = Join-Path $root "build-driver.ps1"
$sys = Join-Path $root "x64\$Configuration\gpuc-readonly.sys"
$cat = Join-Path $root "gpuc-readonly.cat"
$kitsBinRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
$inf2Cat = Get-ChildItem $kitsBinRoot -Recurse -Filter "Inf2Cat.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "\\x86\\Inf2Cat.exe$" } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
$signTool = Get-ChildItem $kitsBinRoot -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "\\x64\\signtool.exe$" } |
    Sort-Object FullName -Descending |
    Select-Object -First 1

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

Write-Output "GPUC read-only package audit"
Write-Output ("PackageRoot: " + $root)
Write-Output ("Configuration: " + $Configuration)
Write-Output ""

$infExists = Test-Path $inf
$sysExists = Test-Path $sys
Write-Check "INF exists" $infExists $inf
Write-Check "SYS exists" $sysExists $sys
if (-not $infExists -or -not $sysExists) {
    $failed = $true
}

if ($infExists) {
    $infText = Get-Content -LiteralPath $inf -Raw
    $hasTargetHardware = $infText -match [regex]::Escape("ACPI\APP000B")
    $hasBroadAcpiWildcard = $infText -match "ACPI\\\*|ACPI\\.*\*"
    $hasKernelService = $infText -match "ServiceType\s*=\s*1"
    $hasDemandStart = $infText -match "StartType\s*=\s*3"
    $hasKmdf115 = $infText -match "KmdfLibraryVersion\s*=\s*1\.15"
    $hasCatalog = $infText -match "CatalogFile\s*=\s*gpuc-readonly\.cat"

    Write-Output ""
    Write-Output "INF review:"
    Write-Check "Hardware match is ACPI\APP000B" $hasTargetHardware "expected exact Apple mux hardware ID"
    Write-Check "No broad ACPI wildcard match" (-not $hasBroadAcpiWildcard) ("BroadWildcard=" + $hasBroadAcpiWildcard)
    Write-Check "Kernel service declared" $hasKernelService "ServiceType=1"
    Write-Check "Demand start declared" $hasDemandStart "StartType=3"
    Write-Check "KMDF 1.15 declared" $hasKmdf115 "KmdfLibraryVersion=1.15"
    Write-Check "Catalog file declared" $hasCatalog "CatalogFile=gpuc-readonly.cat"

    if (-not $hasTargetHardware -or $hasBroadAcpiWildcard -or -not $hasKernelService -or -not $hasDemandStart -or -not $hasKmdf115 -or -not $hasCatalog) {
        $failed = $true
    }
}

$forbiddenDefines = @(
    "GPUC_ENABLE_REPORTED_RESOURCE_READ"
)

Write-Output ""
Write-Output "Compile flag review:"
foreach ($define in $forbiddenDefines) {
    $activeInProject = $false
    if (Test-Path $project) {
        $projectText = Get-Content -LiteralPath $project -Raw
        $activeInProject = $projectText -match "<PreprocessorDefinitions>[^<]*$([regex]::Escape($define))[^<]*</PreprocessorDefinitions>"
    }

    $activeInBuildScript = $false
    if (Test-Path $buildScript) {
        $buildText = Get-Content -LiteralPath $buildScript -Raw
        $activeInBuildScript = $buildText -match "(/D|DefineConstants|PreprocessorDefinitions)[^`r`n]*$([regex]::Escape($define))"
    }

    $isSafe = -not $activeInProject -and -not $activeInBuildScript
    Write-Check ("Forbidden define absent: " + $define) $isSafe ("Project=" + $activeInProject + "; BuildScript=" + $activeInBuildScript)
    if (-not $isSafe) {
        $failed = $true
    }
}

if ($sysExists) {
    $sysItem = Get-Item $sys
    $sysHash = Get-FileHash -Algorithm SHA256 $sys
    Write-Output ""
    Write-Output "SYS artifact:"
    Write-Output ("  Path: " + $sysItem.FullName)
    Write-Output ("  SizeBytes: " + $sysItem.Length)
    Write-Output ("  SHA256: " + $sysHash.Hash)
}

Write-Output ""
Write-Output "Allowed future package payload:"
Write-Output ("  " + $inf)
Write-Output ("  " + $sys)
Write-Output ("  " + $cat + " (only after catalog generation is explicitly allowed)")
Write-Output ""
Write-Output "WDK tools:"
Write-Check "Inf2Cat available" ($null -ne $inf2Cat) $(if ($inf2Cat) { $inf2Cat.FullName } else { "missing" })
Write-Check "SignTool available" ($null -ne $signTool) $(if ($signTool) { $signTool.FullName } else { "missing" })

if ($GenerateCatalog) {
    if ($null -eq $inf2Cat) {
        throw "Cannot generate catalog because Inf2Cat.exe was not found."
    }

    Write-Output ""
    Write-Output "Generating catalog. This does not sign, stage, install, bind, or load the driver."
    & $inf2Cat.FullName /driver:$root /os:10_X64
    if ($LASTEXITCODE -ne 0) {
        throw "Inf2Cat failed with exit code $LASTEXITCODE"
    }

    if (Test-Path $cat) {
        $catItem = Get-Item $cat
        $catHash = Get-FileHash -Algorithm SHA256 $cat
        Write-Output ("CatalogPath: " + $catItem.FullName)
        Write-Output ("CatalogSizeBytes: " + $catItem.Length)
        Write-Output ("CatalogSha256: " + $catHash.Hash)
    }
} else {
    Write-Output ""
    Write-Output "Catalog generation skipped. Re-run with -GenerateCatalog only after explicit approval."
}

if ($failed) {
    Write-Output ""
    Write-Output "Package audit failed. Build the driver before continuing."
    exit 2
}

Write-Output ""
Write-Output "Package audit completed. No signing, staging, install, service creation, driver load, or binding was performed."
