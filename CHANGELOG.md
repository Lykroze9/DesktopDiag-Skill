# Changelog

All notable changes to DesktopDiag. Format: newest first. / Les nouveautés de DesktopDiag, les plus récentes en premier.

## Unreleased

- The skill now has its own repository (DesktopDiag-Skill). The standalone Windows app lives in [DesktopDiag](https://github.com/Lykroze9/DesktopDiag) and embeds this skill's scripts and rules.

## 0.3.0 - 2026-11-20

### Added
- **Shared rules and computed score**: `rules/rules.json` + `scripts/score.ps1`. The same PC always
  gets the same score; the rules will be shared with the standalone app.
- **New checks**: Windows Memory Diagnostic result, battery health via `powercfg /batteryreport`
  (design vs current capacity, cycles), network health (Wi-Fi signal, router ping, DNS time,
  Wi-Fi and Ethernet drops), page file and hibernation file sizes.
- New report areas: Network, Battery (laptops only).
- `scripts/summarize.ps1` (the `-Summary` digest, now testable on its own).
- Tests: `tests/run-tests.ps1` with synthetic fixtures (no real machine data), GitHub Actions CI
  with PSScriptAnalyzer.
- Bilingual issue templates, Discussions, this changelog.

## 0.2.0 - 2026-11-20

### Added
- `collect.ps1 -Summary`: compact digest, about 10x smaller, used by the skill by default.
- Boot time: firmware time per boot, Fast Startup; admin step: total boot time and boot slowdowns,
  with detection of a stale boot log.
- CPU throttling (Kernel-Processor-Power 37), live performance limit, ACPI thermal zones.
- `references/performance.md`.

## 0.1.0 - 2026-11-19

- First public version: read-only collection (stability, GPU, storage, SMART, hardware errors,
  security, performance, maintenance), admin deep scan (SMART, dump analysis, volume scan),
  history and comparison, FR/EN reports, follow-up scheduling.
