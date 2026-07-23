param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root "gpuc-readonly.vcxproj"
$msbuild = "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe"
$kitsRoot = "C:\Program Files (x86)\Windows Kits\10"
$kmIncludeRoot = Join-Path $kitsRoot "Include"
$kmLibRoot = Join-Path $kitsRoot "Lib"
$detectedKmInclude = Get-ChildItem $kmIncludeRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "km\ntddk.h") } |
    Sort-Object Name -Descending |
    Select-Object -First 1
$sdkVersion = if ($detectedKmInclude) { $detectedKmInclude.Name } else { "10.0.26100.0" }
$sdkInclude = Join-Path $kmIncludeRoot "$sdkVersion\km"
$sdkLib = Join-Path $kmLibRoot "$sdkVersion\km\x64"
$kernelToolset = "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Microsoft\VC\v180\Platforms\x64\PlatformToolsets\WindowsKernelModeDriver10.0"
$userToolset = "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Microsoft\VC\v180\Platforms\x64\PlatformToolsets\WindowsUserModeDriver10.0"
$wdfHeader = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10" -Recurse -Filter "wdf.h" -ErrorAction SilentlyContinue | Select-Object -First 1
$wdfEntryLib = Get-ChildItem (Join-Path $kitsRoot "Lib\wdf\kmdf\x64") -Recurse -Filter "WdfDriverEntry.lib" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1

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

Write-Output ("DetectedSdkVersion: " + $sdkVersion)
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

& $msbuild $project /m `
    /p:Configuration=$Configuration `
    /p:Platform=x64 `
    /p:WindowsTargetPlatformVersion=$sdkVersion `
    /p:SignMode=Off `
    /p:EnableTestSign=false `
    /p:EnableInf2cat=false `
    /p:ApiValidator_Enable=false `
    /t:Build
if ($LASTEXITCODE -ne 0) {
    throw "Driver build failed with exit code $LASTEXITCODE"
}

$artifact = Join-Path $root "x64\$Configuration\gpuc-readonly.sys"
if (Test-Path $artifact) {
    $artifactItem = Get-Item $artifact
    $artifactHash = Get-FileHash -Algorithm SHA256 $artifact
    Write-Output ("ArtifactPath: " + $artifactItem.FullName)
    Write-Output ("ArtifactSizeBytes: " + $artifactItem.Length)
    Write-Output ("ArtifactSha256: " + $artifactHash.Hash)
}

Write-Output "Build completed. No install, signing, service creation, or driver load was performed."
