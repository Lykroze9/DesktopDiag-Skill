---
name: desktopdiag
description: Read-only Windows PC health check and troubleshooting. Use when the user asks to check, diagnose or audit their Windows PC, or reports crashes, blue screens (BSOD), freezes, black screens, display driver resets, random reboots, slowness, overheating, disk or SSD problems, or asks "is my PC OK". Also in French - "check du PC", "checking du PC", "diagnostic PC", "mon PC plante", "écran bleu", "écran noir", "freeze", "le PC redémarre tout seul", "PC lent", "santé du SSD". Collects data with PowerShell (no admin needed), compares with previous checks, and writes a scored report in the user's language (French or English).
---

# DesktopDiag

Read-only health check for Windows 10/11 PCs. Works with the built-in Windows PowerShell 5.1.

**Golden rule: collect and explain, never change.** The collection scripts only read. Any fix is
a proposal the user must approve, action by action (see `references/remediation.md`).

**Language:** answer in the user's language. French and English report templates are in
`references/report.md`. If unclear, use the language of the user's last message.

## Workflow

### 1. Pick the mode from the request

| Mode | When | What to do |
|---|---|---|
| **Quick** | "check my PC", "is everything OK" | Collect, report all areas briefly. |
| **Symptom** | The user describes a problem | Collect, then focus the report on areas linked to the symptom (table below). Ask one clarifying question only if the symptom is too vague to act on. |
| **Deep** | Crashes with unclear cause, disk worries, or the user asks for a full check | Quick/Symptom first, then propose the admin step (step 4). |

| Symptom (EN / FR) | Look first at | Reference |
|---|---|---|
| Blue screen / écran bleu | `stability.bugchecks`, `unexpectedShutdowns`, `minidumps` | `bsod.md` |
| Black screen, frozen image, driver reset / écran noir, image figée | `gpuEvents`, `hardware.gpus`, startup OC tools, `unexpectedShutdowns` code 0x0 | `gpu.md` |
| Reboots on its own / redémarre tout seul | `unexpectedShutdowns`, `hardwareErrors`, `bugchecks` | `bsod.md`, `events.md` |
| Slow / lent | `load`, `storage.volumes`, `maintenance.startup`, `diskEvents`, `thermal` | `storage.md`, `performance.md` |
| Slow to start / long à démarrer | `boot`, `maintenance.startup`, admin `bootPerformance` | `performance.md` |
| Overheating, fans loud / chauffe, ventilos à fond | `thermal`, disk temperatures, `load` | `performance.md` |
| Disk, SSD, USB drive / disque, SSD, clé USB | `storage`, `diskEvents` | `storage.md` |
| Game crashes / jeux qui plantent | `appCrashes`, `gpuEvents`, `stability` | `gpu.md` |
| Security worries / sécurité | `security` | `report.md` |
| Internet drops, slow Wi-Fi / internet qui coupe, Wi-Fi lent | `networkHealth`, `network` | `more-checks.md` |
| Battery drains fast / batterie qui se vide vite | `battery`, `load` | `more-checks.md` |
| Random crashes, suspect RAM / plantages aléatoires, RAM | `memoryDiagnostics`, `hardwareErrors`, `bugchecks` | `more-checks.md`, `bsod.md` |
| C: full / disque C: plein | `storage.volumes`, `maintenance` (pagefile, hibernation, temp, downloads) | `storage.md`, `more-checks.md` |

### 2. Collect

Run from the skill directory (replace `<skill-dir>` with this skill's folder):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\collect.ps1" -Summary
```

- Takes about 30-60 s. Saves the full snapshot to `%LOCALAPPDATA%\DesktopDiag\history\<timestamp>.json` and prints a **compact JSON digest** (about 10x smaller): key figures, event groups with count/first/last, no long lists. **Work from the digest.**
- Open the full snapshot (path in `fullSnapshot`) only when you need detail the digest leaves out: every timestamp of an event group, event message samples, startup commands, full process lists, RAM modules, monitors, recent boots one by one. Read only the section you need.
- Options: `-Days 7` (general error window), `-CrashDays 30` (crash/GPU/disk window), `-Full` (adds pending winget upgrades and a driver inventory, slower), `-Anonymize -OutFile <path>` (share mode), `-NoSave` (do not add to history), `-Stdout` (print the full JSON instead).
- `meta.needsAdmin` lists what could not be read without admin (normal). `meta.collectErrors` lists real failures: mention them only if they hide something important.

### 3. Compare with the previous check

If the history holds an earlier snapshot:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\compare.ps1"
```

It prints JSON: free space deltas, crashes/GPU/disk/hardware/CPU-throttling events **new since
the previous snapshot**, firmware boot time vs before, driver/BIOS/build changes, startup entries added or removed, devices newly failing or
fixed. Use it for the "Since last check" section. Skip silently if `comparable` is false.

### 3b. Score

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\score.ps1"
```

It applies `rules/rules.json` to the newest snapshot and prints the score, each area's level
(green / yellow / red / skipped) and the findings that set it, in the snapshot's language
(`-Lang fr|en` to force). After the admin step, run it again with `-Admin <admin json>` (SMART and
boot time can change disk health and boot levels). **Use this score and these levels as they are**
so the same PC always gets the same score. Each area also carries `details` (what exactly was found: crash dates and stop codes in plain words, the culprit driver when the admin dump analysis found one, which disk, which programs...) and `culprits` (known driver -> software and what to do, from `rules/knowledge.json`): quote them so the user knows concretely what is wrong. You add the explanations, the context (e.g. a red that
comes from an old cause already fixed: say so in the text) and the recommendations. If you think a
level is wrong, keep it and say why in one line; the rule can be fixed later. `-Full` adds the
computed facts if you need to see why a rule fired.

### 4. Optional admin deep scan

Propose it when it would change the conclusion: SSD health needed, crash dumps to analyse,
file system doubts, slow boot (it reads the full boot duration and what slowed each boot down). Explain that a Windows admin prompt will appear. Then:

```powershell
Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<skill-dir>\scripts\collect-admin.ps1','-OutFile','<scratch>\dd-admin.json'
```

Add `'-Dumps'` to analyse recent minidumps with WinDbg's `cdb` (if installed; downloads Microsoft
symbols the first time) and `'-Sfc'` for a read-only system file check (several minutes). It
returns reliability counters, boot performance (total boot time, boot slowdowns), SMART via
smartctl if installed, and a read-only `Repair-Volume -Scan`.
If smartctl or WinDbg is missing, the JSON includes the `winget install` command: offer it, do not
install without a yes.

### 5. Analyse

Load only the references you need:

- `references/events.md` - meaning of every event group, what is benign.
- `references/bsod.md` - stop codes, crash patterns, culprit drivers.
- `references/gpu.md` - TDR, black screens, triage order.
- `references/storage.md` - free space, SMART/NVMe thresholds, disk errors.
- `references/performance.md` - boot time, CPU throttling, temperatures.
- `references/more-checks.md` - RAM test, battery, network, page file and hibernation file.
- `references/report.md` - scoring rubric and FR/EN templates. **Always load before writing the report.**
- `references/remediation.md` - risk levels and safe execution. Load before proposing any fix.
- `references/followup.md` - follow-up cadence, scheduling, prompt templates. Load before scheduling.

Cross-check before concluding:
- Map disk errors to the right physical disk (USB vs system SSD).
- Count crashes from the System log only (the collector already does).
- A single old event is not a trend; look at `first`, `last` and `count`.
- Distinguish facts from hypotheses in the report.

### 6. Report

Follow `references/report.md`: score and area levels from `score.ps1`, table of areas, "since last check", what matters,
3-5 recommendations (each saying whether you can do it after their OK or they must do it),
what was not checked, and the proposed next check (step 7).

### 7. Propose the next check (every time)

End every report by proposing a follow-up check, sized to what was found: a one-time check in
2-4 days after a fix or while a problem is active, weekly while recent red items settle, monthly
for yellow-only or all-green PCs. Ask before scheduling (one question with the date/frequency).
On a yes, schedule it with the local scheduled-task tool if available, with a self-contained
prompt carrying this check's key numbers and known causes. Rules, time-zone handling, duplicate
handling and FR/EN prompt templates: `references/followup.md`. **Load it before scheduling.**

If this run is itself a scheduled follow-up, re-evaluate the cadence at the end (switch weekly to
monthly when nothing new appears, or shorten it when a new red item shows up) and update the
existing task instead of creating a new one.

### 8. Fixes (only on request)

Follow `references/remediation.md`. One action at a time, exact command shown first, explicit yes
required, verify afterwards. Never delete user data, clear logs, disable security, or edit the
registry/BIOS on your own initiative. After a fix, step 7 applies: propose a check in 3-4 days.

## Privacy

Everything stays on the PC. Nothing is uploaded, except Microsoft symbol downloads when the user
accepts dump analysis. Snapshots in the history folder contain machine details: use `-Anonymize`
before sharing anything outside.
