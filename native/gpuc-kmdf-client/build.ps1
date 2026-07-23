param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Join-Path $root "bin\$Configuration"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$vsRoot = "C:\Program Files\Microsoft Visual Studio\18\Community"
$vcvars = Join-Path $vsRoot "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
    throw "vcvars64.bat not found. Install Visual Studio C++ build tools."
}

$source = Join-Path $root "gpuc-kmdf-client.cpp"
$exe = Join-Path $outDir "gpuc-kmdf-client.exe"

$batch = Join-Path $outDir "build.cmd"
@"
@echo off
call "$vcvars"
if errorlevel 1 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /DUNICODE /D_UNICODE "$source" /Fe"$exe" setupapi.lib
exit /b %errorlevel%
"@ | Set-Content -Path $batch -Encoding ASCII

cmd.exe /c "`"$batch`""
if ($LASTEXITCODE -ne 0) {
    throw "Native client build failed with exit code $LASTEXITCODE"
}

Write-Output $exe
