---
name: desktopdiag
description: Read-only Windows PC health check and troubleshooting. Use when the user asks to check, diagnose or audit their Windows PC, or reports crashes, blue screens (BSOD), freezes, black screens, display driver resets, random reboots, slowness, overheating, disk or SSD problems, or asks "is my PC OK". Also in French - "check du PC", "checking du PC", "diagnostic PC", "mon PC plante", "écran bleu", "écran noir", "freeze", "le PC redémarre tout seul", "PC lent", "santé du SSD". Collects data with PowerShell (no admin needed), compares with previous checks, and writes a scored report in the user's language (French or English).
---

# DesktopDiag

Read-only health check for Windows 10/11, with the built-in Windows PowerShell 5.1.

**Golden rule: collect and explain, never change.** Scripts only read. Any fix is a proposal the
user approves action by action (`references/remediation.md`).

**Language:** the user's language (last message if unclear). FR/EN templates: `references/report.md`.

## Workflow

### 1. Pick the mode

| Mode | When | Do |
|---|---|---|
| **Quick** | "check my PC", "is everything OK" | Collect, report all areas briefly. |
| **Symptom** | A described problem | Collect, focus on the linked areas (table). One clarifying question only if too vague to act on. |
| **Deep** | Unclear crashes, disk worries, "full check" | Quick/Symptom first, then propose step 4. |

| Symptom (EN / FR) | Look first at | Reference |
|---|---|---|
| Blue screen / écran bleu | `stability.bugchecks`, `unexpectedShutdowns`, `minidumps` | `bsod.md` |
| Black screen, frozen image, driver reset / écran noir, image figée | `gpuEvents`, `hardware.gpus`, startup OC tools, shutdowns code 0x0 | `gpu.md` |
| Reboots on its own / redémarre tout seul | `unexpectedShutdowns`, `hardwareErrors`, `bugchecks` | `bsod.md`, `events.md` |
| Slow / lent | `load`, `storage.volumes`, `maintenance.startup`, `diskEvents`, `thermal` | `storage.md`, `performance.md` |
| Slow to start / long à démarrer | `boot`, `maintenance.startup`, admin `bootPerformance` | `performance.md` |
| Overheating / chauffe, ventilos à fond | `thermal`, disk temperatures, `load` | `performance.md` |
| Disk, SSD, USB drive / disque, SSD, clé USB | `storage`, `diskEvents` | `storage.md` |
| Game crashes / jeux qui plantent | `appCrashes`, `gpuEvents`, `stability` | `gpu.md` |
| Security / sécurité | `security` | `report.md` |
| Internet drops, slow Wi-Fi / internet qui coupe | `networkHealth`, `network` | `more-checks.md` |
| Battery drains / batterie qui se vide | `battery`, `load` | `more-checks.md` |
| Random crashes, RAM / plantages aléatoires | `memoryDiagnostics`, `hardwareErrors`, `bugchecks` | `more-checks.md`, `bsod.md` |
| C: full / disque C: plein | `storage.volumes`, `maintenance` (pagefile, hibernation, temp) | `storage.md`, `more-checks.md` |

### 2. Collect

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\collect.ps1" -Summary
```

- 30-60 s. Saves the full snapshot to `%LOCALAPPDATA%\DesktopDiag\history\<timestamp>.json` and prints a compact digest (about 10x smaller). **Work from the digest**; open the full snapshot (`fullSnapshot`) only for detail it leaves out (every event timestamp, message samples, startup commands, process lists, RAM modules, boots one by one), and read only that section.
- Options: `-Days 7`, `-CrashDays 30`, `-Full` (winget upgrades + driver inventory, slower), `-Anonymize -OutFile <path>` (share mode), `-NoSave`, `-Stdout`.
- `meta.needsAdmin` is normal; mention `meta.collectErrors` only if they hide something important.

### 3. Compare and score

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\compare.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\score.ps1"
```

- `compare.ps1`: what is **new since the previous snapshot** (space deltas, crashes, GPU/disk/hardware/throttling events, boot time, driver/BIOS/build and startup changes, devices failing or fixed). Feeds "Since last check"; skip silently if `comparable` is false.
- `score.ps1` applies `rules/rules.json`: score, each area's level (green/yellow/red/skipped) and findings, in the snapshot's language (`-Lang fr|en`). After step 4, rerun with `-Admin <admin json>`. **Use the score and levels as they are** (same PC, same score); if a level looks wrong, keep it and say why in one line. `-Full` adds the computed facts.
- Each area has `details` (crash dates and stop codes in plain words, culprit driver from dump analysis, which disk, which programs...) and `culprits` (driver -> software -> what to do, from `rules/knowledge.json`): **quote them** so the user knows concretely what is wrong. You add context (e.g. a red caused by something already fixed) and recommendations.

### 4. Optional admin deep scan

Propose it when it would change the conclusion (SSD health, crash dumps, file system doubts, slow
boot). Warn that a Windows admin prompt will appear:

```powershell
Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<skill-dir>\scripts\collect-admin.ps1','-OutFile','<scratch>\dd-admin.json'
```

`'-Dumps'` analyses recent minidumps with WinDbg's `cdb` (downloads Microsoft symbols the first
time); `'-Sfc'` runs a read-only system file check (minutes). Returns reliability counters, boot
performance, SMART (smartctl) and a read-only `Repair-Volume -Scan`. If smartctl or WinDbg is
missing, the JSON gives the `winget install` command: offer it, never install without a yes.

### 5. Analyse

Load only what you need:
`events.md` (event groups, what is benign) · `bsod.md` (stop codes, culprit drivers) · `gpu.md`
(TDR, black screens) · `storage.md` (space, SMART/NVMe thresholds) · `performance.md` (boot,
throttling, temperatures) · `more-checks.md` (RAM test, battery, network, pagefile/hibernation) ·
`report.md` (**always before the report**) · `remediation.md` (before any fix) · `followup.md`
(before scheduling). All in `references/`.

Before concluding: map disk errors to the right physical disk (USB vs system SSD); count crashes
from the System log only (done by the collector); one old event is not a trend (`first`, `last`,
`count`); separate facts from hypotheses.

### 6. Report

Per `report.md`: score and levels from `score.ps1`, areas table, "since last check", what matters,
3-5 recommendations (each says whether you can do it after their OK or they must), what was not
checked, and the next check (step 7).

### 7. Propose the next check (every time)

Size it to the findings: once in 2-4 days after a fix or while a problem is active, weekly while red
items settle, monthly otherwise. One question with the date/frequency; on a yes, schedule it with
the local scheduled-task tool and a self-contained prompt (key numbers, known causes). Rules and
FR/EN templates: `followup.md`, **load it first**. If this run is a scheduled follow-up, re-evaluate
the cadence and update the existing task instead of creating one.

### 8. Fixes (only on request)

Per `remediation.md`: one action at a time, exact command first, explicit yes, verify after. Never
delete user data, clear logs, disable security, or edit registry/BIOS on your own initiative. After a
fix, propose a check in 3-4 days.

## Privacy

Everything stays on the PC, except Microsoft symbol downloads when dump analysis is accepted.
Snapshots contain machine details: use `-Anonymize` before sharing.
