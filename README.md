<div align="center">

<img src="docs/icon.png" width="116" alt="Seeubot" />

# Seeubot

**A cute, live Dynamic-Island widget for your Mac notch that tracks your Claude Code & Codex sessions.**

**English** · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Windows](https://img.shields.io/badge/Windows-planned%20preview-0078D4?logo=windows)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue)
![No Xcode](https://img.shields.io/badge/build-no%20Xcode%20needed-brightgreen)

<img src="docs/demo.gif" width="720" alt="Seeubot demo" />

</div>

---

## What is it

Seeubot lives in your Mac's **notch**. At a glance it shows how many AI coding sessions are running, how many are **working** vs **idle**, and how many tokens they've burned — with a cute robot mascot that blinks, glances around and chatters when work is happening. Hover it and it springs open into a full dashboard.

Everything is read **locally** from the session files Claude Code and Codex already write to disk. No network, no API keys, no telemetry.

## Features

- 🏝️ **Lives in the notch** — a small pill that expands into a dashboard on hover.
- 🤖 **Animated mascot** — blinks, looks around, tilts, hops, sways its antenna and throws off sparkles while work happens; dozes with `zzz` when idle.
- 📊 **Live dashboard** — total sessions, working vs idle, token throughput (output / input / cache-create / cache-read), Claude vs Codex split, and a chip per live session.
- 🎛️ **Two forms** — a pill **hanging** below the notch, or a **bar** across it. On Macs **without** a notch it shows as one flat bar automatically.
- 🖱️ **Menu everywhere** — a `⋯` button in the dashboard *and* a menu-bar icon: show/hide, switch form, check for updates, and **quit**.
- 🔔 **Update checks** — tells you when a new version is out.
- 🪶 **Tiny & native** — one SwiftUI binary, builds with the Command Line Tools (**no Xcode**), no dependencies.

<div align="center">
<img src="docs/expanded.png" width="380" alt="Dashboard" />
</div>

## Install

### macOS

### One-line script

Builds from source, installs to `/Applications`, starts now and auto-starts at login:

```bash
curl -fsSL https://raw.githubusercontent.com/ChestonChen/Seeubot/main/install.sh | bash
```

### From source

```bash
git clone https://github.com/ChestonChen/Seeubot.git
cd Seeubot && ./install.sh
```

> Apple-silicon Mac, **macOS 14+**, with the Command Line Tools (`xcode-select --install`). No Xcode required.

### Windows preview

Windows source is isolated under `apps/windows/` and keeps the same product idea: a floating Dynamic-Island style pill near the top of the screen, expanding into the dashboard on hover.

```powershell
iwr -useb https://raw.githubusercontent.com/ChestonChen/Seeubot/main/install.ps1 | iex
```

The Windows installer prefers a GitHub Release package, then falls back to the checked-in Windows zip under `apps/windows/release/`. Source builds are still available for contributors with Git, Node.js and Rust.

## Source layout

- macOS source: `Sources/`, `build.sh`, `install.sh`
- Windows source: `apps/windows/`

## Usage

- **Hover** the widget → it opens into the dashboard. Move away → it collapses. (Collapsed, it never blocks clicks underneath.)
- **`⋯` button** in the dashboard, or the **menu-bar gauge icon** → switch form, show/hide, check for updates, **Quit**.

## Forms

| Hanging (notch) | Bar (notch) | Flat (no notch) |
|:---:|:---:|:---:|
| <img src="docs/collapsed-hanging.png" width="230"/> | <img src="docs/collapsed-sides.png" width="230"/> | <img src="docs/collapsed-flat.png" width="230"/> |

## How it works

Every **3 seconds** a background collector reads local files:

| Metric | Source |
|--------|--------|
| Claude sessions & tokens | `~/.claude/projects/**/<uuid>.jsonl` — sums each `assistant` message's usage, **de-duplicated by `message.id`** (skips `subagents/`) |
| Codex sessions & tokens | `~/.codex/sessions/**/rollout-*.jsonl` — the last cumulative `token_count` |
| Today's tokens | attributed by each entry's **timestamp** |
| Live sessions | running `claude` / `codex` processes (`ps` + `lsof` for cwd / open transcript) |
| Working vs idle | transcript written within **45 s** → *working*, otherwise *idle* |

Token totals are parsed once and **cached per file** (size + mtime), so each tick only re-reads the sessions currently being written. Hover is detected by polling the cursor, so the panel never steals focus.

> Token totals can reach billions because they include **cache reads** (context re-read every turn). The dashboard breaks this out and highlights *Output* — the tokens actually generated.

## Roadmap

- [x] Menu-bar + in-widget control (show/hide, switch form, quit)
- [x] Non-notch Macs (flat bar)
- [x] Update checks
- [x] Homebrew cask
- [ ] 🔔 **Desktop popup when a session finishes — _next up_.** Agents rarely tell you the moment a long task is done; Seeubot will pop a notification the second a session goes from *working* to idle.
- [ ] 🔌 More AI CLIs — Cursor, Aider, Gemini CLI, Cline, opencode…
- [ ] ⚙️ Configurable refresh interval & "working" window
- [ ] 💵 Cost estimation (tokens → $ per model)
- [ ] 📈 History & trends
- [ ] 🧭 In-app auto-update

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.chestonchen.seeubot.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.chestonchen.seeubot.plist
rm -rf /Applications/Seeubot.app
```

## FAQ

**Does it only track Claude Code and Codex?** Yes for now — other tools store sessions differently and need per-tool adapters (see roadmap).

**Is it automatic?** Fully. It re-scans every 3 seconds and starts at login; tokens accumulate as you work.

**Does it send my data anywhere?** No. It only reads local files under `~/.claude` and `~/.codex`.

## Contributing

Issues and PRs welcome — adapters for more AI CLIs, translations and UI polish are great first contributions.

## License

[MIT](LICENSE)
