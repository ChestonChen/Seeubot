# Changelog

All notable changes to Seeubot are documented here. This project follows
[Semantic Versioning](https://semver.org/) and its releases live on
[GitHub Releases](https://github.com/ChestonChen/Seeubot/releases).

## [Unreleased]

### Planned
- 🔔 **Desktop popup when a session finishes** (next up) — notify the moment a
  session goes from *working* to idle.

## [1.0] — 2026-07-06

First public release. A live notch (Dynamic-Island) widget for macOS that tracks
Claude Code & Codex sessions.

### Added
- Notch widget with a collapsed pill/bar that expands into a live dashboard on hover.
- Real-time stats: total sessions, working vs idle, and token throughput
  (output / input / cache-create / cache-read), split by Claude vs Codex.
- Animated **Seeubot** mascot (blink, glance, hop, antenna sway, sparkles, `zzz`).
- Two forms on notched Macs (**hanging** pill / **bar**) and an automatic flat bar
  on Macs without a notch.
- Menu-bar icon **and** an in-widget `⋯` menu: switch form, show/hide, check for
  updates, and quit.
- Update checks against GitHub Releases (badge + menu item when a new version is out).
- Install via a one-line script or from source (`./install.sh`); auto-starts at login.
- 100% local — reads only `~/.claude` and `~/.codex`; no network, keys or telemetry.

### Accuracy
- Claude tokens de-duplicated by `message.id` (a response spans many transcript lines).
- `subagents/` sidechains excluded from session counts and totals.
- "Today" attributed by per-entry timestamp, not file mtime.
- Distinct transcripts assigned to sessions sharing one working directory.
