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
$kernelToolset = "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Microsoft\VC\v180\Platforms\x64\PlatformToolsets\WindowsKernelModeDriver10.0"
$userToolset = "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Microsoft\VC\v180\Platforms\x64\PlatformToolsets\WindowsUserModeDriver10.0"
$wdfHeader = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10" -Recurse -Filter "wdf.h" -ErrorAction SilentlyContinue | Select-Object -First 1
$wdfEntryLib = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10" -Recurse -Filter "WdfDriverEntry.lib" -ErrorAction SilentlyContinue | Select-Object -First 1

$checks = [ordered]@{
    Project = (Test-Path $project)
    MSBuild = (Test-Path $msbuild)
    KernelToolset = (Test-Path $kernelToolset)
    UserModeDriverToolset = (Test-Path $userToolset)
    KernelHeaders = (Test-Path $sdkInclude)
    KernelLibs = (Test-Path $sdkLib)
    WdfHeader = ($null -ne $wdfHeader)
    WdfEntryLib = ($null -ne $wdfEntryLib)
}

foreach ($item in $checks.GetEnumerator()) {
    Write-Output ("{0}: {1}" -f $item.Key, $item.Value)
}

if (Test-Path $kernelToolset) {
    Write-Output ("KernelToolsetPath: " + $kernelToolset)
}

if ($wdfHeader) {
    Write-Output ("WdfHeaderPath: " + $wdfHeader.FullName)
}

if ($wdfEntryLib) {
    Write-Output ("WdfEntryLibPath: " + $wdfEntryLib.FullName)
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
