param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\captures\gpu-process-watch"),
    [int]$Samples = 12,
    [int]$IntervalSeconds = 5,
    [switch]$Redact
)

$ErrorActionPreference = "Continue"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $OutputDirectory $stamp
New-Item -ItemType Directory -Force -Path $out | Out-Null
$reportPath = Join-Path $out "gpu-process-watch.md"
$csvPath = Join-Path $out "gpu-process-watch.csv"

function Get-GpuEngineSamples {
    $samples = Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction SilentlyContinue
    if (-not $samples) {
        return @()
    }

    foreach ($sample in $samples.CounterSamples) {
        if ($sample.CookedValue -le 0.01) {
            continue
        }
        if ($sample.Path -notmatch 'pid_([0-9]+)') {
            continue
        }

        $pidValue = [int]$Matches[1]
        $processName = "unknown"
        try {
            $processName = (Get-Process -Id $pidValue -ErrorAction Stop).ProcessName
        } catch {}

        $engine = "unknown"
        if ($sample.Path -match 'engtype_([^_\\)]+)') {
            $engine = $Matches[1]
        }

        [pscustomobject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
            Pid = if ($Redact) { "<redacted-pid>" } else { $pidValue }
            ProcessName = $processName
            Engine = $engine
            Utilization = [math]::Round([double]$sample.CookedValue, 4)
            CounterPath = if ($Redact) { "<redacted-counter-path>" } else { $sample.Path }
        }
    }
}

$all = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $Samples; $i++) {
    foreach ($row in @(Get-GpuEngineSamples)) {
        $all.Add($row)
    }
    if ($i -lt ($Samples - 1)) {
        Start-Sleep -Seconds $IntervalSeconds
    }
}

$all | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

"# GPU Process Watch" | Set-Content -Path $reportPath -Encoding UTF8
Add-Content -Path $reportPath -Value "" -Encoding UTF8
Add-Content -Path $reportPath -Value ("Timestamp: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")) -Encoding UTF8
Add-Content -Path $reportPath -Value "" -Encoding UTF8
Add-Content -Path $reportPath -Value "Mode: read-only GPU Engine performance counter sampling. No settings are changed." -Encoding UTF8
Add-Content -Path $reportPath -Value "" -Encoding UTF8
Add-Content -Path $reportPath -Value ("Samples: " + $Samples) -Encoding UTF8
Add-Content -Path $reportPath -Value ("IntervalSeconds: " + $IntervalSeconds) -Encoding UTF8
Add-Content -Path $reportPath -Value "" -Encoding UTF8
Add-Content -Path $reportPath -Value "## Top Processes" -Encoding UTF8
Add-Content -Path $reportPath -Value "" -Encoding UTF8

$top = @($all |
    Group-Object ProcessName,Engine |
    ForEach-Object {
        $rows = @($_.Group)
        [pscustomobject]@{
            ProcessName = $rows[0].ProcessName
            Engine = $rows[0].Engine
            Samples = $rows.Count
            TotalUtilization = [math]::Round((($rows | Measure-Object Utilization -Sum).Sum), 4)
            PeakUtilization = [math]::Round((($rows | Measure-Object Utilization -Maximum).Maximum), 4)
        }
    } |
    Sort-Object TotalUtilization -Descending |
    Select-Object -First 20)

if ($top.Count -eq 0) {
    Add-Content -Path $reportPath -Value "- No GPU Engine counters above threshold were observed." -Encoding UTF8
} else {
    foreach ($entry in $top) {
        Add-Content -Path $reportPath -Value ("- " + $entry.ProcessName) -Encoding UTF8
        Add-Content -Path $reportPath -Value ("  - Engine: " + $entry.Engine) -Encoding UTF8
        Add-Content -Path $reportPath -Value ("  - Samples: " + $entry.Samples) -Encoding UTF8
        Add-Content -Path $reportPath -Value ("  - TotalUtilization: " + $entry.TotalUtilization) -Encoding UTF8
        Add-Content -Path $reportPath -Value ("  - PeakUtilization: " + $entry.PeakUtilization) -Encoding UTF8
    }
}

Write-Output $reportPath
Write-Output $csvPath
