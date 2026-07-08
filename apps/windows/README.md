# Seeubot for Windows

Windows source lives here and is intentionally isolated from the existing macOS Swift source at the repository root.

## Product Shape

Seeubot for Windows is a lightweight resident widget:

- A floating Dynamic-Island style pill centered near the top of the screen.
- Hover the pill to expand into a dashboard.
- A system tray menu keeps the app controllable without a traditional main window.
- The UI mirrors the macOS dashboard: Sessions, Working, Idle, Total Tokens, agent split and Live Sessions.

## Install

From PowerShell:

```powershell
iwr -useb https://raw.githubusercontent.com/ChestonChen/Seeubot/main/install.ps1 | iex
```

The installer prefers a GitHub Release zip. If no Windows release exists yet, it falls back to the checked-in zip at `apps/windows/release/Seeubot-Windows-x64.zip`. Source builds are still available for contributors with Git, Node.js and Rust.

## Develop

```powershell
cd apps/windows
npm install
npm run tauri:dev
```

Build a Windows package:

```powershell
npm run tauri:build
```

## Data Sources

The Windows collector mirrors the macOS Agent Adapter model:

| Agent | Local source |
| --- | --- |
| Claude | `%USERPROFILE%\.claude\projects/**/*.jsonl` |
| Codex | `%USERPROFILE%\.codex\sessions/**/*.jsonl` |
| Cursor sessions | `%USERPROFILE%\.cursor\projects/**/agent-transcripts/**/*.jsonl` |
| Cursor tokens | `%APPDATA%\Cursor\User\globalStorage\panshenbing.cursor-usage-dashboard\usage-refresh-cache.json` |

Claude and Codex tokens are parsed from local JSONL transcripts. Cursor token totals use the same local usage cache as the macOS implementation because Cursor transcripts do not expose stable per-session usage buckets.

## Uninstall

```powershell
apps/windows/uninstall.ps1
```
