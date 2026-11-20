<#
.SYNOPSIS
    DesktopDiag - compute the area levels and the score of a snapshot from rules\rules.json.

.DESCRIPTION
    1. Derives a flat set of "facts" from the snapshot (and the admin snapshot if given).
    2. Evaluates rules.json: each area takes the worst level among its triggered rules.
    3. Score = start - yellow x areas in yellow - red x areas in red (min). Same file is meant to
       be shared with the standalone app, so the same PC always gets the same score.
    Missing data never triggers a rule (a null fact makes a condition false).

.PARAMETER Path
    Snapshot (collect.ps1). Default: newest non-admin snapshot in history.
.PARAMETER Admin
    Optional admin snapshot (collect-admin.ps1) for SMART and boot performance facts.
.PARAMETER Lang
    fr or en. Default: from the snapshot's UI culture.
.PARAMETER Now
    Reference date for "last 7 days" windows. Default: the snapshot timestamp.
.PARAMETER RulesPath
    rules.json to apply. Default: ..\rules\rules.json next to this script (set it when the script
    text is run without a file, as the standalone app does).
.PARAMETER Full
    Include the facts in the output.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [string]$Admin,
    [ValidateSet('', 'fr', 'en')][string]$Lang = '',
    [string]$Now,
    [switch]$Full,
    [string]$RulesPath
)

$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture

function Read-Json { param([string]$P) [IO.File]::ReadAllText($P, [Text.Encoding]::UTF8) | ConvertFrom-Json }

if (-not $Path) {
    $histDir = Join-Path $env:LOCALAPPDATA 'DesktopDiag\history'
    $Path = (Get-ChildItem -LiteralPath $histDir -Filter '*.json' | Where-Object { $_.Name -notmatch '-admin\.json$' } |
        Sort-Object Name -Descending | Select-Object -First 1).FullName
}
$s = Read-Json $Path
$a = if ($Admin -and (Test-Path -LiteralPath $Admin)) { Read-Json $Admin } else { $null }
if (-not $RulesPath) { $RulesPath = Join-Path $PSScriptRoot '..\rules\rules.json' }
$rules = Read-Json $RulesPath

$ref = if ($Now) { [datetime]$Now } else { [datetime]$s.meta.timestamp }
if (-not $Lang) { $Lang = if ("$($s.meta.uiCulture)" -like 'fr*') { 'fr' } else { 'en' } }

# ------------------------------------------------------------------ helpers
function Get-DaysAgo { param($Iso) if ($Iso) { [math]::Round(($ref - [datetime]$Iso).TotalDays) } else { $null } }
function Get-TimesWithin {
    param($Groups, [int]$Days)
    $limit = $ref.AddDays(-$Days)
    $n = 0
    foreach ($g in @($Groups | Where-Object { $_ })) {
        $times = @($g.times | Where-Object { $_ })
        if ($times.Count) { $n += @($times | Where-Object { [datetime]$_ -ge $limit }).Count }
        elseif ($g.last -and [datetime]$g.last -ge $limit) { $n += [int]$g.count }
    }
    $n
}
function Get-Sum { param($Groups) $t = 0; foreach ($g in @($Groups | Where-Object { $_ })) { $t += [int]$g.count }; $t }
function Get-Max { param($Values) $v = @($Values | Where-Object { $null -ne $_ }); if ($v.Count) { ($v | Measure-Object -Maximum).Maximum } else { $null } }

# ------------------------------------------------------------------ facts
$f = [ordered]@{}

# Stability: a blue screen leaves a Kernel-Power 41 and a 1001; merge times within 15 min.
$crashTimes = New-Object System.Collections.Generic.List[datetime]
foreach ($t in @(@($s.stability.unexpectedShutdowns | ForEach-Object { $_.time }) + @($s.stability.bugchecks | ForEach-Object { $_.time })) | Where-Object { $_ } | ForEach-Object { [datetime]$_ } | Sort-Object) {
    if (-not ($crashTimes | Where-Object { [math]::Abs(($_ - $t).TotalMinutes) -lt 15 })) { $crashTimes.Add($t) }
}
$f.crashes30d = @($crashTimes | Where-Object { $_ -ge $ref.AddDays(-30) }).Count
$f.crashes7d = @($crashTimes | Where-Object { $_ -ge $ref.AddDays(-7) }).Count
$f.reliabilityIndex = if ($s.stability.reliabilityIndex) { [double]$s.stability.reliabilityIndex.index } else { $null }

# Graphics
$f.gpuErrors30d = Get-TimesWithin $s.gpuEvents 30
$f.gpuErrors7d = Get-TimesWithin $s.gpuEvents 7
$gpuAges = @($s.hardware.gpus | Where-Object { $_.driverDate -and $_.name -notmatch 'Microsoft Basic|Remote|Virtual' } | ForEach-Object { Get-DaysAgo $_.driverDate })
$f.gpuDriverAgeDays = Get-Max $gpuAges
$f.gpuDeviceError = [bool](@($s.problemDevices | Where-Object { $_ -and $_.class -eq 'Display' -and @(10, 43) -contains [int]$_.errorCode }).Count)

# Storage space
$sysDrive = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
$vols = @($s.storage.volumes | Where-Object { $_ -and $_.type -eq 'fixed' })
$sysVol = $vols | Where-Object { $_.drive -eq $sysDrive } | Select-Object -First 1
if (-not $sysVol) { $sysVol = $vols | Select-Object -First 1 }
$f.systemFreePct = if ($sysVol) { [double]$sysVol.freePct } else { $null }
$f.systemFreeGB = if ($sysVol) { [double]$sysVol.freeGB } else { $null }
$dataPcts = @($vols | Where-Object { $_.drive -ne $sysVol.drive } | ForEach-Object { [double]$_.freePct })
$f.dataMinFreePct = if ($dataPcts.Count) { ($dataPcts | Measure-Object -Minimum).Minimum } else { $null }

# Disk health
$disks = @($s.storage.physicalDisks | Where-Object { $_ })
$f.diskUnhealthy = [bool](@($disks | Where-Object { $_.health -and $_.health -ne 'Healthy' }).Count)
$wear = @($disks | ForEach-Object { if ($_.reliability) { $_.reliability.wearPct } })
$unc = @($disks | ForEach-Object { if ($_.reliability) { $_.reliability.readUncorrected } })
$f.readUncorrected = Get-Max $unc
$f.smartFailed = $null; $f.smartMediaErrors = $null; $f.ssdWarningTempMinutes = $null
if ($a -and $a.smart -and $a.smart.devices) {
    $dev = @($a.smart.devices)
    $f.smartFailed = [bool](@($dev | Where-Object { $_.smartPassed -eq $false }).Count)
    $media = 0
    foreach ($d in $dev) {
        if ($d.nvme) { $media += [int]$d.nvme.mediaErrors; if ($d.nvme.criticalWarning) { $media += 1 }; $wear += $d.nvme.percentageUsed }
        foreach ($attr in @($d.ata | Where-Object { $_ -and @(5, 197, 198) -contains [int]$_.id })) { $media += [int64]$attr.raw }
    }
    $f.smartMediaErrors = $media
    $f.ssdWarningTempMinutes = Get-Max @($dev | ForEach-Object { if ($_.nvme) { $_.nvme.warningTempMinutes } })
}
$f.maxWearPct = Get-Max $wear
# Serious disk errors (disk 7/51, Ntfs 55) on an internal (non-USB) disk; retries 153/129 anywhere.
$busByNumber = @{}; foreach ($d in $disks) { $busByNumber["$($d.number)"] = "$($d.bus)" }
$internal = 0; $retries = 0
foreach ($g in @($s.diskEvents | Where-Object { $_ })) {
    $num = if ($g.key -match 'Harddisk(\d+)') { $Matches[1] } else { $null }
    $isUsb = $num -and $busByNumber[$num] -eq 'USB'
    if ($g.key -match '^(disk/(7|51)|Ntfs/55|Microsoft-Windows-Ntfs/55)\b' -and -not $isUsb) { $internal += [int]$g.count }
    if ($g.key -match '^(disk/153|stornvme/129|storahci/129)\b') { $retries += [int]$g.count }
}
$f.internalDiskErrors = $internal
$f.diskRetries = $retries

# Hardware errors
$wheaFatalIds = @('WHEA/18', 'WHEA/20', 'WHEA/46')
$f.wheaFatal = Get-Sum @($s.hardwareErrors | Where-Object { $_ -and $wheaFatalIds -contains $_.key })
$f.wheaCorrected = Get-Sum @($s.hardwareErrors | Where-Object { $_ -and $wheaFatalIds -notcontains $_.key })
$f.tpmErrors = Get-Sum $s.tpmEvents
$f.ramTestErrors = if ($s.memoryDiagnostics -and $null -ne $s.memoryDiagnostics.errorsFound) { [bool]$s.memoryDiagnostics.errorsFound } else { $null }
$devs = @($s.problemDevices | Where-Object { $_ })
$keyClasses = @('Display', 'Net', 'DiskDrive', 'SCSIAdapter', 'HDC', 'System', 'Processor')
$f.keyDeviceErrors = @($devs | Where-Object { $keyClasses -contains $_.class -and @(10, 43) -contains [int]$_.errorCode -and $_.present -ne $false }).Count
$f.otherDeviceErrors = @($devs | Where-Object { $_.present -ne $false }).Count - $f.keyDeviceErrors

# Security
$sec = $s.security
$f.antivirusActive = if ($sec) { [bool](@($sec.antivirusProducts | Where-Object { $_.enabled }).Count -or ($sec.defender -and $sec.defender.antivirusEnabled)) } else { $null }
$f.realTimeOff = if ($sec -and $sec.defender -and "$($sec.defender.mode)" -eq 'Normal') { -not [bool]$sec.defender.realTime } else { $null }
$f.firewallOff = if ($sec) { @($sec.firewall | Where-Object { $_ -and -not $_.enabled }).Count } else { $null }
$f.signatureAgeDays = if ($sec -and $sec.defender -and "$($sec.defender.mode)" -eq 'Normal') { $sec.defender.signatureAgeDays } else { $null }
$f.wuLastSuccessDays = if ($sec -and $sec.windowsUpdate) { Get-DaysAgo $sec.windowsUpdate.lastSuccess } else { $null }
$f.wuFailures = if ($sec -and $sec.windowsUpdate) { @($sec.windowsUpdate.recentFailures | Where-Object { $_ }).Count } else { $null }
$f.uacOff = if ($sec -and $null -ne $sec.uacEnabled) { -not [bool]$sec.uacEnabled } else { $null }

# Performance now
$f.ramUsedPct = $s.load.ramUsedPct
$f.commitUsedPct = $s.load.commitUsedPct
$f.topProcessCpuPct = Get-Max @($s.load.topCpu | Where-Object { $_ -and $_.name -notmatch '^(System|Idle|_Total)$' } | ForEach-Object { $_.cpuPct })

# Boot
$f.firmwareSec = if ($s.boot) { $s.boot.lastFirmwareSec } else { $null }
$bp = if ($a) { $a.bootPerformance } else { $null }
$f.adminBootSec = if ($bp -and -not $bp.stale) { $bp.lastBootSec } else { $null }
$f.bootSlowdownSec = if ($bp -and -not $bp.stale) { Get-Max @($bp.slowdowns | Where-Object { $_ -and [int]$_.count -ge 2 } | ForEach-Object { $_.avgDelaySec }) } else { $null }

# Heat
$f.throttle30d = if ($s.thermal) { Get-TimesWithin $s.thermal.cpuThrottleEvents 30 } else { $null }
$f.throttle7d = if ($s.thermal) { Get-TimesWithin $s.thermal.cpuThrottleEvents 7 } else { $null }
$f.perfLimitPct = if ($s.thermal) { $s.thermal.cpuPerfLimitPct } else { $null }
$f.maxThermalZoneC = if ($s.thermal) { Get-Max @($s.thermal.thermalZones | ForEach-Object { $_.temperatureC }) } else { $null }
$f.isLaptop = [bool]$s.hardware.isLaptop
$f.onBattery = if ($s.battery) { [int]$s.battery.status -eq 1 } else { $false }

# Network
$nh = $s.networkHealth
$f.dnsOk = if ($nh) { [bool]$nh.dnsOk } else { $null }
$f.dnsMs = if ($nh) { $nh.dnsMs } else { $null }
$f.gatewayPingMs = if ($nh) { $nh.gatewayPingMs } else { $null }
$f.wifiSignalPct = if ($nh -and $nh.wifi) { $nh.wifi.signalPct } else { $null }
$f.disconnects7d = if ($nh) { Get-TimesWithin $nh.disconnects 7 } else { $null }

# Battery
$f.batteryHealthPct = if ($s.battery) { $s.battery.healthPct } else { $null }

# Maintenance
$f.rebootPending = if ($sec) { [bool]$sec.rebootPending } else { $null }
$f.uptimeDays = $s.system.uptimeDays
$f.startupCount = $s.maintenance.startupCount
$f.tempGB = if ($s.maintenance) { [math]::Round([double]$s.maintenance.userTempGB + [double]$s.maintenance.windowsTempGB, 1) } else { $null }

# ------------------------------------------------------------------ rule engine
function Test-Condition {
    param($C)
    if ($null -eq $C) { return $true }
    if ($C.PSObject.Properties.Name -contains 'all') { foreach ($x in $C.all) { if (-not (Test-Condition $x)) { return $false } }; return $true }
    if ($C.PSObject.Properties.Name -contains 'any') { foreach ($x in $C.any) { if (Test-Condition $x) { return $true } }; return $false }
    $v = $f[$C.fact]
    if ($null -eq $v) { return $false }
    $w = $C.value
    switch ($C.op) {
        '>'  { return [double]$v -gt [double]$w }
        '>=' { return [double]$v -ge [double]$w }
        '<'  { return [double]$v -lt [double]$w }
        '<=' { return [double]$v -le [double]$w }
        '==' { if ($w -is [bool]) { return [bool]$v -eq $w } else { return "$v" -eq "$w" } }
        '!=' { if ($w -is [bool]) { return [bool]$v -ne $w } else { return "$v" -ne "$w" } }
        default { throw "Unknown operator $($C.op)" }
    }
}

function Format-Text {
    param([string]$T)
    [regex]::Replace($T, '\{(\w+)\}', { param($m) $x = $f[$m.Groups[1].Value]; if ($null -eq $x) { '?' } else { "$x" } })
}

# ------------------------------------------------------------------ concrete details
# What exactly was found on this PC, per area (dates, codes, culprit driver, disk, programs...),
# worded with rules\knowledge.json (phrases, drivers, stop codes) so this script stays ASCII.
$details = @{}
$culprits = New-Object System.Collections.Generic.List[object]
$kFile = Join-Path (Split-Path -Parent $RulesPath) 'knowledge.json'
$k = if (Test-Path -LiteralPath $kFile) { Read-Json $kFile } else { $null }
function Add-Detail { param([string]$Area, [string]$Text) if (-not $details.ContainsKey($Area)) { $details[$Area] = New-Object System.Collections.Generic.List[string] }; $details[$Area].Add($Text) }
function Get-Phrase {
    param([string]$Key, [hashtable]$V)
    $tpl = $k.templates.$Key.$Lang
    [regex]::Replace($tpl, '\{(\w+)\}', { param($m) $x = $V[$m.Groups[1].Value]; if ($null -eq $x) { '' } else { "$x" } }).Replace(' ()', '').Trim()
}
function Format-When { param($Iso) if (-not $Iso) { return '?' }; $d = [datetime]$Iso; if ($Lang -eq 'fr') { $d.ToString('dd/MM/yyyy HH:mm') } else { $d.ToString('yyyy-MM-dd HH:mm') } }
function Format-Num { param($X) $t = "$X"; if ($Lang -eq 'fr') { $t.Replace('.', ',') } else { $t } }
function Get-StopCode { param([string]$Raw) if ($Raw -match '0x([0-9a-fA-F]+)') { '0x' + ([Convert]::ToInt64($Matches[1], 16)).ToString('x') } else { $null } }

if ($k) {
    # Stability: each crash of the last 30 days, its stop code in plain words, and the culprit
    # driver when the admin dump analysis found one for that crash.
    $limit = $ref.AddDays(-30)
    $dumps = if ($a -and $a.dumpAnalysis -and $a.dumpAnalysis.results) { @($a.dumpAnalysis.results) } else { @() }
    $events = @()
    foreach ($b in @($s.stability.bugchecks | Where-Object { $_ -and $_.time })) {
        $events += [pscustomobject]@{ time = [datetime]$b.time; code = (Get-StopCode "$($b.bugcheck)"); bsod = $true }
    }
    foreach ($u in @($s.stability.unexpectedShutdowns | Where-Object { $_ -and $_.time })) {
        $t = [datetime]$u.time
        if (-not ($events | Where-Object { [math]::Abs(($_.time - $t).TotalMinutes) -lt 15 })) {
            $code = Get-StopCode "$($u.bugcheckCode)"
            $events += [pscustomobject]@{ time = $t; code = $code; bsod = ($code -and $code -ne '0x0') }
        }
    }
    $needDump = $false
    foreach ($e in @($events | Where-Object { $_.time -ge $limit } | Sort-Object time -Descending | Select-Object -First 5)) {
        $sc = if ($e.code) { $k.stopCodes."$($e.code)" } else { $null }
        if (-not $e.bsod) { Add-Detail 'stability' (Get-Phrase 'crashOff' @{ date = (Format-When $e.time); meaning = $k.stopCodes.'0x0'.$Lang }); continue }
        Add-Detail 'stability' (Get-Phrase 'crashBsod' @{ date = (Format-When $e.time); code = $e.code; name = $(if ($sc) { $sc.name }); meaning = $(if ($sc) { $sc.$Lang }) })
        $dump = @($dumps | Where-Object { $_.date -and [math]::Abs(([datetime]$_.date - $e.time).TotalMinutes) -lt 15 }) | Select-Object -First 1
        $file = if ($dump) { @($dump.imageName, $dump.moduleName) | Where-Object { $_ } | Select-Object -First 1 } else { $null }
        if ($file) {
            $kd = $k.drivers."$($file.ToLower())"
            Add-Detail 'stability' (Get-Phrase 'crashCulprit' @{ file = $file; product = $(if ($kd) { $kd.product } else { '?' }) })
            if ($kd -and -not ($culprits | Where-Object { $_.file -eq $file })) { $culprits.Add([ordered]@{ area = 'stability'; file = $file; product = $kd.product; advice = $kd.$Lang }) }
        } elseif (-not $dumps.Count) { $needDump = $true }
    }
    if ($needDump) { Add-Detail 'stability' (Get-Phrase 'crashNoDump' @{}) }
    foreach ($c in @($s.appCrashes.crashes | Where-Object { $_ } | Sort-Object { [int]$_.count } -Descending | Select-Object -First 3)) {
        Add-Detail 'stability' (Get-Phrase 'appCrash' @{ app = ("$($c.key)" -replace '\s*\[.*$', ''); count = $c.count; date = (Format-When $c.last) })
    }

    # Graphics: which driver, how many resets/errors and when; the card and its driver; OC tools.
    $vendors = @{ nvlddmkm = 'NVIDIA'; amdkmdag = 'AMD'; atikmdag = 'AMD'; amdwddmg = 'AMD'; igfx = 'Intel'; igfxn = 'Intel' }
    foreach ($g in @($s.gpuEvents | Where-Object { $_ })) {
        $parts = "$($g.key)" -split '/'
        $kind = if ($parts.Count -gt 1 -and $parts[1] -in '153', '4101') { 'gpuReset' } else { 'gpuError' }
        $vendor = if ($vendors.ContainsKey($parts[0])) { $vendors[$parts[0]] } else { $parts[0] }
        Add-Detail 'graphics' (Get-Phrase $kind @{ vendor = $vendor; count = $g.count; first = (Format-When $g.first); last = (Format-When $g.last) })
    }
    foreach ($c in @($s.hardware.gpus | Where-Object { $_ })) {
        $ver = if ($c.nvidiaVersion) { $c.nvidiaVersion } else { $c.driverVersion }
        Add-Detail 'graphics' (Get-Phrase 'gpuCard' @{ name = $c.name; version = $ver; date = $(if ($c.driverDate) { ([datetime]$c.driverDate).ToString($(if ($Lang -eq 'fr') { 'dd/MM/yyyy' } else { 'yyyy-MM-dd' })) } else { '?' }) })
    }
    $oc = @($s.maintenance.startup | Where-Object { $_ -and "$($_.name) $($_.command)" -match 'Afterburner|RTSS|RivaTuner|Ryzen ?Master|Precision ?X|GPU ?Tweak|ThrottleStop|XTU' } | ForEach-Object { $_.name })
    if ($oc.Count) { Add-Detail 'graphics' (Get-Phrase 'ocTools' @{ list = ($oc -join ', ') }) }

    # Disks: which physical disk the errors are on (number -> model and bus: USB or internal).
    foreach ($g in @($s.diskEvents | Where-Object { $_ })) {
        if ("$($g.key)" -match 'Harddisk(\d+)\\') {
            $n = $Matches[1]
            $pd = @($s.storage.physicalDisks | Where-Object { "$($_.number)" -eq $n }) | Select-Object -First 1
            Add-Detail 'diskHealth' (Get-Phrase 'diskEvent' @{ count = $g.count; kind = $($id = ("$($g.key)" -split ' ')[0].ToLower(); $de = $k.diskEvents.$id; if ($de) { $de.$Lang } else { $id }); n = $n; disk = $(if ($pd) { $pd.name } else { '?' }); bus = $(if ($pd) { $pd.bus }); last = (Format-When $g.last) })
        }
    }

    # Space: every fixed volume, plus temp and hibernation files.
    foreach ($v in @($s.storage.volumes | Where-Object { $_ -and $_.type -eq 'fixed' })) {
        Add-Detail 'storageSpace' (Get-Phrase 'volume' @{ drive = $v.drive; free = (Format-Num $v.freeGB); size = (Format-Num $v.sizeGB); pct = (Format-Num $v.freePct) })
    }
    $temp = [math]::Round([double]$s.maintenance.userTempGB + [double]$s.maintenance.windowsTempGB, 1)
    $hiber = if ($s.maintenance.hibernation) { [double]$s.maintenance.hibernation.hiberfilGB } else { 0 }
    if ($temp -ge 1) { Add-Detail 'storageSpace' (Get-Phrase 'tempFiles' @{ temp = (Format-Num $temp) }) }
    if ($hiber -ge 1) { Add-Detail 'storageSpace' (Get-Phrase 'hiberFile' @{ hiber = (Format-Num $hiber) }) }

    # Performance: who used the memory and the processor during the check.
    $tm = @($s.load.topMemory | Where-Object { $_ } | Select-Object -First 4 | ForEach-Object { '{0} ({1} {2})' -f $_.name, (Format-Num ([math]::Round([double]$_.memMB / 1024, 1))), $(if ($Lang -eq 'fr') { 'Go' } else { 'GB' }) })
    if ($tm.Count) { Add-Detail 'performance' (Get-Phrase 'topMem' @{ list = ($tm -join ', ') }) }
    $tc = @($s.load.topCpu | Where-Object { $_ -and [double]$_.cpuPct -ge 5 } | Select-Object -First 3 | ForEach-Object { '{0} ({1} %)' -f $_.name, (Format-Num $_.cpuPct) })
    if ($tc.Count) { Add-Detail 'performance' (Get-Phrase 'topCpu' @{ list = ($tc -join ', ') }) }

    # Maintenance: startup programs (and which ones are safe to turn off), uptime.
    $st = @($s.maintenance.startup | Where-Object { $_ } | ForEach-Object { "$($_.name)" -replace ' - (Raccourci|Shortcut)$', '' } | Where-Object { $_ -notmatch '^MicrosoftEdgeAutoLaunch_' })
    if ($s.maintenance.startup | Where-Object { "$($_.name)" -match '^MicrosoftEdgeAutoLaunch_' }) { $st += 'Microsoft Edge' }
    if ($st.Count) {
        Add-Detail 'maintenance' (Get-Phrase 'startupList' @{ count = $st.Count; list = (($st | Select-Object -First 12) -join ', ') })
        $safe = @($st | Where-Object { $n = ($_.ToLower() -replace '[^a-z0-9.]', ''); @($k.startupSafe | Where-Object { $n -like "*$_*" }).Count -gt 0 })
        if ($safe.Count) { Add-Detail 'maintenance' (Get-Phrase 'startupSafe' @{ list = ($safe -join ', ') }) }
    }
    if ($s.system.uptimeDays -ge 7) { Add-Detail 'maintenance' (Get-Phrase 'uptime' @{ days = [math]::Floor([double]$s.system.uptimeDays) }) }

    # Hardware: devices in error with their code in plain words, WHEA errors.
    foreach ($d in @($s.problemDevices | Where-Object { $_ } | Select-Object -First 6)) {
        $m = $k.deviceCodes."$($d.errorCode)"
        Add-Detail 'hardwareErrors' (Get-Phrase 'device' @{ name = $d.name; code = $d.errorCode; meaning = $(if ($m) { $m.$Lang }) })
    }
    foreach ($g in @($s.hardwareErrors | Where-Object { $_ })) {
        Add-Detail 'hardwareErrors' (Get-Phrase 'whea' @{ count = $g.count; kind = ("$($g.key)" -replace '^WHEA/', '#'); last = (Format-When $g.last) })
    }

    # Security: which updates failed. Network: drops. Heat: throttling.
    $wuf = @($s.security.windowsUpdate.recentFailures | Where-Object { $_ } | Select-Object -First 3 | ForEach-Object { ("$($_.title) $($_.hresult)").Trim() })
    if ($wuf.Count) { Add-Detail 'security' (Get-Phrase 'wuFail' @{ list = ($wuf -join ' ; ') }) }
    $drops = @($s.networkHealth.disconnects | Where-Object { $_ })
    if ($drops.Count) {
        $last = ($drops | ForEach-Object { $_.last } | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1)
        Add-Detail 'network' (Get-Phrase 'netDrops' @{ count = (Get-Sum $drops); last = (Format-When $last) })
    }
    $thr = @($s.thermal.cpuThrottleEvents | Where-Object { $_ })
    if ($thr.Count) { Add-Detail 'heat' (Get-Phrase 'throttle' @{ count = (Get-Sum $thr); last = (Format-When ($thr | Select-Object -First 1).last) }) }
}

$rank = @{ green = 0; yellow = 1; red = 2 }
$areas = @()
$yellow = 0; $red = 0
foreach ($area in $rules.areas) {
    $label = $area.label.$Lang
    if ($area.PSObject.Properties.Name -contains 'appliesWhen' -and -not (Test-Condition $area.appliesWhen)) {
        $areas += [ordered]@{ id = $area.id; label = $label; level = 'skipped'; findings = @(); details = @(); culprits = @() }
        continue
    }
    $findings = @(foreach ($r in $area.rules) {
        if (Test-Condition $r.when) { [ordered]@{ id = $r.id; level = $r.level; text = Format-Text $r.text.$Lang } }
    })
    $level = 'green'
    foreach ($x in $findings) { if ($rank[$x.level] -gt $rank[$level]) { $level = $x.level } }
    # Keep only the most severe finding per area level family (red ones, else yellow ones).
    $shown = @($findings | Where-Object { $_.level -eq $level })
    if ($level -eq 'yellow') { $yellow++ } elseif ($level -eq 'red') { $red++ }
    $areas += [ordered]@{ id = $area.id; label = $label; level = $level; findings = $shown
        details = @(if ($details.ContainsKey($area.id)) { $details[$area.id] })
        culprits = @($culprits | Where-Object { $_.area -eq $area.id }) }
}
$sc = $rules.scoring
$score = [math]::Max([int]$sc.min, [int]$sc.start - [int]$sc.yellow * $yellow - [int]$sc.red * $red)

$out = [ordered]@{
    score       = $score
    lang        = $Lang
    rulesVersion = $rules.version
    snapshot    = $Path
    admin       = if ($a) { $Admin } else { $null }
    counts      = [ordered]@{ red = $red; yellow = $yellow; green = @($areas | Where-Object { $_.level -eq 'green' }).Count }
    areas       = $areas
}
if ($Full) { $out.facts = $f }
$out | ConvertTo-Json -Depth 6 -Compress
