# DesktopDiag for Claude Code

### Is your PC slow, glitchy, crashing... or do you just want a quick checkup?

**A read-only Windows PC health check skill for [Claude Code](https://claude.com/claude-code).** Ask
"check my PC" or describe a problem ("my screen goes black in games", "random reboots") and Claude
collects the data, explains it in plain language, scores your PC and tells you what to do next.
Reports in **English or French**.

> **🖥️ No Claude?** The same checks exist as a free, portable Windows app:
> **[DesktopDiag](https://github.com/Lykroze9/DesktopDiag)** (one 1 MB file, nothing to install, one click).

[🇫🇷 Version française](README.fr.md)

> **👋 A personal side project.** DesktopDiag started as a custom tool I built for my own PC, after
> chasing GPU freezes and blue screens, and grew into a skill I wanted to share. It is not a
> commercial product and it is far from finished.
>
> **Your feedback is very welcome!** Tried it? Found a bug, a wrong diagnosis, a missing check, or
> just have an idea? Please [open an issue](https://github.com/Lykroze9/DesktopDiag-Skill/issues) or start a
> [discussion](https://github.com/Lykroze9/DesktopDiag-Skill/discussions), in English or French. Every comment helps make the skill better.

## Install

As a Claude Code plugin:

```
/plugin marketplace add Lykroze9/DesktopDiag-Skill
/plugin install desktopdiag@desktopdiag
```

Or as a standalone skill: copy `skills/desktopdiag` to `%USERPROFILE%\.claude\skills\desktopdiag`
(all projects) or to `.claude\skills\desktopdiag` in a project.

## Use

Just talk to Claude Code:

- "Check my PC" / "Is my PC healthy?"
- "My screen goes black for a few seconds when I play"
- "My PC rebooted by itself twice this week"
- "Is my SSD OK?"
- "Do a full check" (proposes the admin deep scan)
- "Make a shareable report for a forum"
- "Schedule a check every month" / "Check again in 4 days"

## What it checks

| Area | Details |
|---|---|
| Stability | Blue screens (stop code + parameters), unexpected shutdowns, crash dumps, Windows reliability index |
| Graphics | Display driver resets (TDR), NVIDIA/AMD/Intel driver errors, driver version and age, overclocking tools at startup |
| Storage | Free space, disk health, SSD wear/temperature/errors (SMART via smartctl), disk errors mapped to the right drive (USB vs system SSD) |
| Hardware | WHEA hardware errors (CPU, RAM, PCIe), Windows Memory Diagnostic result, TPM errors, devices in error (code 10/43...) |
| Security | Antivirus status, firewall profiles, last successful Windows Update and recent failures, pending reboot, UAC, Secure Boot |
| Performance | Real CPU % (sampled, not cumulative), RAM and commit usage, top processes |
| Boot time | Firmware/BIOS time of each boot, Fast Startup; with admin: total boot time and what slowed each boot down (app, driver, service) |
| Heat | CPU throttling by firmware (heat or power limits), live performance limit, thermal zones when the PC exposes them |
| Network | Wi-Fi signal, router ping, DNS response time, Wi-Fi and Ethernet drops |
| Battery | Laptops: health (current vs original capacity) and charge cycles |
| Maintenance | Startup entries, temp folders, uptime, page file and hibernation file size |
| History | Every check is saved locally and compared with the previous one: new crashes since last time, space lost, driver/BIOS updates, startup entries added |
| Follow-up | After each report, Claude proposes the next check sized to what it found (in 2-4 days after a fix, weekly while problems settle, monthly otherwise) and schedules it on your OK with the Claude desktop app's local scheduled tasks |

## Why another one?

Existing Windows diagnostic skills/MCP servers skip the problems people actually hit: GPU driver
resets, NVMe wear, BSOD culprit drivers, and "did it get better since last week?". DesktopDiag
also:

- runs on the **built-in Windows PowerShell 5.1** (no PowerShell 7, Node or Python needed), Windows 10 and 11;
- needs **no admin** for the main check; an optional admin step adds SMART, dump analysis and a read-only file system scan;
- is **read-only**: fixes are proposed with risk levels and run only after your explicit OK;
- documents real-world traps (inflated crash counts in the Application log, `chkdsk` access denied, vendor utilities reinstalling drivers, sandboxed registry writes...);
- has a **share mode** that strips user name, computer name and paths for forum posts.

## Scripts

You can also run the collector yourself:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills\desktopdiag\scripts\collect.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File skills\desktopdiag\scripts\compare.ps1
```

Add `-Summary` to `collect.ps1` for a compact digest (about 10x smaller than the full snapshot).
Claude uses it by default, so each check costs far fewer tokens. Snapshots are stored in
`%LOCALAPPDATA%\DesktopDiag\history` (shared with the Windows app).

## Score

The score and the area levels come from `skills/desktopdiag/rules/rules.json`, applied by
`scripts/score.ps1`: the same PC always gets the same score, and Claude adds the explanations.
Thresholds are documented in [rules/README.md](skills/desktopdiag/rules/README.md). The
[Windows app](https://github.com/Lykroze9/DesktopDiag) embeds these same scripts and rules.

## Development

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Live
```

Tests use synthetic snapshots (`tests/fixtures.ps1`, no real machine data) and run on every push
with GitHub Actions, together with PSScriptAnalyzer. See [CHANGELOG.md](CHANGELOG.md) for what changed.

## Optional tools

- [smartmontools](https://www.smartmontools.org/) (`winget install smartmontools.smartmontools`) for detailed SSD/HDD SMART data.
- WinDbg (`winget install Microsoft.WinDbg`) to identify the driver behind a blue screen. The first analysis downloads public symbols from Microsoft.

## Privacy

Everything runs locally. Nothing is uploaded (except Microsoft symbol downloads if you accept dump
analysis). Disk serial numbers are hashed. Use share mode before posting a report anywhere.

## Disclaimer

DesktopDiag reads system information and gives advice. It does not replace a technician. Hardware
interventions (BIOS updates, repasting, part replacement) are your decision and responsibility.

## License

MIT
