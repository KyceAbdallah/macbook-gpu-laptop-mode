param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root "gpuc-readonly.vcxproj"
$msbuild = "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe"
$sdkVersion = "10.0.26100.0"
$sdkInclude = "C:\Program Files (x86)\Windows Kits\10\Include\$sdkVersion\km"
$sdkLib = "C:\Program Files (x86)\Windows Kits\10\Lib\$sdkVersion\km\x64"
$driverTargets = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild" -Recurse -Filter "Microsoft.DriverKit*.targets" -ErrorAction SilentlyContinue | Select-Object -First 1

$checks = [ordered]@{
    Project = (Test-Path $project)
    MSBuild = (Test-Path $msbuild)
    KernelHeaders = (Test-Path $sdkInclude)
    KernelLibs = (Test-Path $sdkLib)
    DriverTargets = ($null -ne $driverTargets)
}

foreach ($item in $checks.GetEnumerator()) {
    Write-Output ("{0}: {1}" -f $item.Key, $item.Value)
}

if ($driverTargets) {
    Write-Output ("DriverTargetsPath: " + $driverTargets.FullName)
}

if ($CheckOnly) {
    if ($checks.Values -contains $false) {
        Write-Output "CheckOnly: WDK build prerequisites are incomplete. No build attempted."
        exit 2
    }

    Write-Output "CheckOnly: WDK build prerequisites appear present. No build attempted."
    exit 0
}

if ($checks.Values -contains $false) {
    throw "WDK build prerequisites are incomplete. Install the matching WDK/VS driver workload before building."
}

& $msbuild $project /m /p:Configuration=$Configuration /p:Platform=x64 /t:Build
if ($LASTEXITCODE -ne 0) {
    throw "Driver build failed with exit code $LASTEXITCODE"
}

Write-Output "Build completed. No install, signing, service creation, or driver load was performed."
