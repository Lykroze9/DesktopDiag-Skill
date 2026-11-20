# rules.json

Single source of truth for area levels and the score, shared by the Claude skill
(`scripts/score.ps1`) and the standalone app (planned). The same snapshot must give the same
levels and score in both.

## Format

```json
{
  "version": 1,
  "scoring": { "start": 100, "yellow": 8, "red": 18, "min": 0 },
  "areas": [
    {
      "id": "battery",
      "label": { "fr": "Batterie", "en": "Battery" },
      "appliesWhen": { "fact": "isLaptop", "op": "==", "value": true },
      "rules": [
        { "id": "battery.worn", "level": "yellow",
          "when": { "fact": "batteryHealthPct", "op": "<", "value": 80 },
          "text": { "fr": "Batterie usée ({batteryHealthPct} %)", "en": "Battery worn ({batteryHealthPct}%)" } }
      ]
    }
  ]
}
```

- **Condition**: `{ "fact", "op", "value" }` with `op` in `> >= < <= == !=`, or `{ "all": [...] }` /
  `{ "any": [...] }`. A fact that is `null` (data not available) makes a simple condition false:
  missing data never raises a level.
- **Area level** = the worst level among its triggered rules (`red` > `yellow`), `green` if none,
  `skipped` if `appliesWhen` is false (not counted in the score).
- **Score** = `start - yellow x (areas in yellow) - red x (areas in red)`, never below `min`.
- **Texts**: `{fact}` placeholders are replaced by the fact value. Every rule needs `fr` and `en`.

## Facts

Computed from a `collect.ps1` snapshot (and optionally a `collect-admin.ps1` one) by
the "facts" section of `scripts/score.ps1`. An implementation in another language must compute the same
facts with the same definitions. "Reference date" = the snapshot timestamp.

| Fact | Definition |
|---|---|
| crashes7d / crashes30d | Kernel-Power 41 and BugCheck 1001 times merged (within 15 min = one crash), within 7 / 30 days |
| reliabilityIndex | `stability.reliabilityIndex.index` |
| gpuErrors7d / gpuErrors30d | Timestamps of all `gpuEvents` groups within 7 / 30 days |
| gpuDriverAgeDays | Oldest driver date among GPUs (excluding Basic/Remote/Virtual adapters), in days |
| gpuDeviceError | A Display-class problem device with code 10 or 43 |
| systemFreePct / systemFreeGB | Free space of the system drive (`%SystemDrive%`, else first fixed volume) |
| dataMinFreePct | Lowest free % among other fixed volumes |
| diskUnhealthy | A physical disk whose health is not `Healthy` |
| readUncorrected | Max uncorrected read errors (Windows reliability counters) |
| smartFailed / smartMediaErrors / ssdWarningTempMinutes | Admin SMART: any failed device; NVMe media errors + critical warning + SATA 5/197/198 raw; max NVMe warning-temperature minutes |
| maxWearPct | Max SSD wear (reliability counters, NVMe percentage used) |
| internalDiskErrors | Count of disk 7/51 and Ntfs 55 events on non-USB disks |
| diskRetries | Count of disk 153 and stornvme/storahci 129 events (any disk) |
| wheaFatal / wheaCorrected | WHEA 18/20/46 counts / other WHEA counts |
| tpmErrors | Sum of `tpmEvents` counts |
| ramTestErrors | Windows Memory Diagnostic last result had errors (null if never run) |
| keyDeviceErrors / otherDeviceErrors | Present problem devices: code 10/43 in Display, Net, DiskDrive, SCSIAdapter, HDC, System, Processor classes / the rest |
| antivirusActive, realTimeOff, firewallOff, signatureAgeDays, wuLastSuccessDays, wuFailures, uacOff | From `security` (Defender values only when Defender is the active antivirus, mode `Normal`) |
| ramUsedPct, commitUsedPct, topProcessCpuPct | From `load` |
| firmwareSec | `boot.lastFirmwareSec` |
| adminBootSec / bootSlowdownSec | Admin boot performance, only when not `stale`: last boot time / max average delay of a slowdown seen at least twice |
| throttle7d / throttle30d | Kernel-Processor-Power 37 timestamps within 7 / 30 days |
| perfLimitPct, maxThermalZoneC | From `thermal` |
| isLaptop, onBattery | `hardware.isLaptop`, battery status 1 |
| dnsOk, dnsMs, gatewayPingMs, wifiSignalPct, disconnects7d | From `networkHealth` |
| batteryHealthPct | `battery.healthPct` |
| rebootPending, uptimeDays, startupCount, tempGB | From `security`, `system`, `maintenance` (user + Windows temp) |

Tests: `tests/run-tests.ps1` runs every fixture in `tests/fixtures.ps1` through the rules. Add a
fixture with each new rule.

## knowledge.json

Plain-language knowledge used by `score.ps1` to word the per-area `details` and `culprits`: phrase templates (FR/EN), drivers often seen in blue screens (software behind them and what to do), stop codes, device error codes, disk event ids and startup programs that are safe to turn off. Keep every template in both languages (a test checks it).
