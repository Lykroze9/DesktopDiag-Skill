<#
.SYNOPSIS
    DesktopDiag test runner. No dependency (no Pester needed). Exit code = number of failures.

.PARAMETER Live
    Also run collect.ps1 on this machine and check the output shape.
#>
[CmdletBinding()]
param([switch]$Live)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $root 'skills\desktopdiag\scripts'
$work = Join-Path ([IO.Path]::GetTempPath()) ('DesktopDiag-tests-{0}' -f $PID)
$null = New-Item -ItemType Directory -Path $work -Force
. (Join-Path $PSScriptRoot 'fixtures.ps1')

$script:failures = 0
$script:passed = 0
function Assert {
    param([bool]$Condition, [string]$Name, [string]$Detail = '')
    if ($Condition) { $script:passed++; Write-Output "  ok   $Name" }
    else { $script:failures++; Write-Output "  FAIL $Name $Detail" }
}
function Save-Snapshot {
    param($Snap, [string]$Name)
    $p = Join-Path $work "$Name.json"
    [IO.File]::WriteAllText($p, ($Snap | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
    $p
}
function Invoke-Script {
    param([string]$Name, [string[]]$Arguments)
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts $Name) @Arguments | Out-String
    if ($LASTEXITCODE -ne 0) { throw "$Name exited with $LASTEXITCODE" }
    $out
}

Write-Output 'Syntax'
foreach ($f in Get-ChildItem (Join-Path $root '*.ps1') -Recurse) {
    $errs = $null
    [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    Assert ($errs.Count -eq 0) "parse $($f.Name)" (($errs | ForEach-Object { $_.Message }) -join '; ')
}
foreach ($f in Get-ChildItem $scripts -Filter *.ps1) {
    $nonAscii = Select-String -LiteralPath $f.FullName -Pattern '[^\x00-\x7F]' | Select-Object -First 1
    Assert (-not $nonAscii) "ascii-only $($f.Name)" $(if ($nonAscii) { "line $($nonAscii.LineNumber)" })
}

Write-Output 'Rules file'
$rules = [IO.File]::ReadAllText((Join-Path $root 'skills\desktopdiag\rules\rules.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$ids = @($rules.areas | ForEach-Object { $_.rules } | ForEach-Object { $_.id })
Assert (@($ids | Group-Object | Where-Object { $_.Count -gt 1 }).Count -eq 0) 'rule ids are unique'
$missing = @($rules.areas | ForEach-Object { $_.rules } | Where-Object { -not $_.text.fr -or -not $_.text.en } | ForEach-Object { $_.id })
Assert ($missing.Count -eq 0) 'every rule has fr and en text' ($missing -join ', ')

Write-Output 'Score (fixtures)'
foreach ($case in Get-DDTestCases) {
    $p = Save-Snapshot $case.snapshot $case.name
    $res = (Invoke-Script 'score.ps1' @('-Path', $p, '-Lang', 'en')) | ConvertFrom-Json
    foreach ($k in $case.expect.Keys) {
        $area = $res.areas | Where-Object { $_.id -eq $k }
        Assert ($area -and $area.level -eq $case.expect[$k]) "$($case.name): $k = $($case.expect[$k])" "(got $($area.level))"
    }
    if ($case.name -eq 'healthy') {
        Assert ($res.score -eq 100) 'healthy: score 100' "(got $($res.score))"
        $bat = $res.areas | Where-Object { $_.id -eq 'battery' }
        Assert ($bat.level -eq 'skipped') 'healthy desktop: battery skipped'
    }
}
$frRes = (Invoke-Script 'score.ps1' @('-Path', (Join-Path $work 'disk-full.json'), '-Lang', 'fr')) | ConvertFrom-Json
$frText = (($frRes.areas | Where-Object { $_.id -eq 'storageSpace' }).findings | Select-Object -First 1).text
Assert ($frText -match 'Disque') 'French text' "(got $frText)"

# Concrete details (knowledge.json): what exactly was found, not just counts.
$bs = (Invoke-Script 'score.ps1' @('-Path', (Join-Path $work 'bsod-recent.json'), '-Lang', 'en')) | ConvertFrom-Json
$bsDet = @(($bs.areas | Where-Object { $_.id -eq 'stability' }).details)
Assert (($bsDet -join ' ') -match 'SYSTEM_SERVICE_EXCEPTION') 'details: stop code in plain words' "(got $($bsDet -join ' | '))"
Assert (($bsDet -join ' ') -match 'deep scan') 'details: hint to find the culprit driver' "(got $($bsDet -join ' | '))"
$gp = (Invoke-Script 'score.ps1' @('-Path', (Join-Path $work 'gpu-tdr.json'), '-Lang', 'fr')) | ConvertFrom-Json
$gpDet = @(($gp.areas | Where-Object { $_.id -eq 'graphics' }).details)
Assert (($gpDet -join ' ') -match 'NVIDIA : 3 r') 'details: GPU driver resets with count (fr)' "(got $($gpDet -join ' | '))"
$kn = [IO.File]::ReadAllText((Join-Path $root 'skills\desktopdiag\rules\knowledge.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$missing = @($kn.templates.PSObject.Properties | Where-Object { -not $_.Value.fr -or -not $_.Value.en } | ForEach-Object { $_.Name })
Assert ($missing.Count -eq 0) 'knowledge: every phrase has fr and en' "(missing: $($missing -join ', '))"

Write-Output 'Compare (fixtures)'
$prev = New-DDSnapshot -At (Get-Date '2026-06-10T12:00:00')
$cur = New-DDSnapshot -At (Get-Date '2026-06-15T12:00:00')
$cur.gpuEvents = @(New-DDGroup 'nvlddmkm/153' @((Get-Date '2026-06-08T10:00:00'), (Get-Date '2026-06-12T10:00:00'), (Get-Date '2026-06-14T10:00:00')))
$cur.storage.volumes[0].freeGB = 380
$cur.maintenance.startup += [ordered]@{ name = 'NewApp'; command = 'x'; location = 'HKU'; hives = 1 }
$cur.hardware.gpus[0].driverVersion = '32.0.15.6100'
$pp = Save-Snapshot $prev 'cmp-prev'; $cp = Save-Snapshot $cur 'cmp-cur'
$cmp = (Invoke-Script 'compare.ps1' @('-Current', $cp, '-Previous', $pp)) | ConvertFrom-Json
Assert ($cmp.comparable) 'compare: comparable'
Assert ((@($cmp.newGpuEvents)[0].newSincePrevious) -eq 2) 'compare: only GPU events after previous snapshot' "(got $(@($cmp.newGpuEvents)[0].newSincePrevious))"
Assert ((@($cmp.volumes)[0].deltaFreeGB) -eq -20) 'compare: free space delta' "(got $(@($cmp.volumes)[0].deltaFreeGB))"
Assert (@($cmp.startup.added) -contains 'NewApp') 'compare: startup entry added'
Assert (@($cmp.versionChanges | Where-Object { $_ -match 'GPU driver' }).Count -eq 1) 'compare: GPU driver change'

Write-Output 'Summary (fixtures)'
$sumJson = Invoke-Script 'summarize.ps1' @('-Path', (Join-Path $work 'gpu-tdr.json'))
$sum = $sumJson | ConvertFrom-Json
Assert ($sumJson.Length -lt 6000) 'summary is compact' "($($sumJson.Length) chars)"
Assert ((@($sum.gpuEvents)[0].count) -eq 3) 'summary keeps event counts'
Assert (-not ($sumJson -match '"times"')) 'summary drops timestamp lists'
Assert ($sum.storage.volumes[0] -match '400/930GB') 'summary uses dot decimals and volume text' "(got $($sum.storage.volumes[0]))"

if ($Live) {
    Write-Output 'Live collect (this machine)'
    $livePath = Join-Path $work 'live.json'
    $digest = (Invoke-Script 'collect.ps1' @('-NoSave', '-OutFile', $livePath, '-Summary')) | ConvertFrom-Json
    foreach ($k in 'system', 'hardware', 'storage', 'stability', 'security', 'boot', 'thermal', 'networkHealth', 'maintenance') {
        Assert ($null -ne $digest.$k) "live: digest has $k"
    }
    Write-Output ("  info collect errors: {0}" -f (@($digest.meta.collectErrors) -join ' | '))
    $sc = (Invoke-Script 'score.ps1' @('-Path', $livePath)) | ConvertFrom-Json
    Assert ($sc.score -ge 0 -and $sc.score -le 100) 'live: score in range' "(got $($sc.score))"
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ''
Write-Output ("{0} passed, {1} failed" -f $script:passed, $script:failures)
exit $script:failures
