# Claude Code — Clawd Toast Notifications

[한국어](README.md) | **English**

Shows a Windows toast notification when Claude Code needs your attention or finishes a task.

| Event | Toast | When it fires |
|---|---|---|
| `Notification` | Clawd + question mark | Permission prompt, idle, etc. (~6s / ~60s delay) |
| `Stop` | Clawd cheering + check | When Claude finishes a response |

The `Notification` delays (about 6 seconds for permission prompts, about 60 seconds for idle) are **hard-coded in Claude Code and cannot be shortened.**

## Install

Double-click `install.bat`. Running Claude Code sessions pick it up within a few seconds — no restart needed.

| File | Action |
|---|---|
| `install.bat` | Install (asks before replacing existing hooks) |
| `settings.bat` | **Open the settings window** |
| `uninstall.bat` | Uninstall |

- `install.bat -Force` replaces existing hooks without asking.
- `install.bat -Language en` sets the display language (`ko` / `en`). If omitted, the current setting is kept; on a first install, the Windows display language is used.

## Language (한국어 / English)

Choose 한국어 or English from **Language** at the bottom right of the settings window. The choice is saved immediately and the window reopens in that language.

The language applies to:

- The settings window
- Toast buttons (Settings / Close ↔ 설정 / 닫기)
- Default messages (`Claude needs your attention.` ↔ `확인이 필요합니다.`, `Task completed.` ↔ `작업이 완료되었습니다.`)
- Install and uninstall messages

Default messages are translated when the toast is shown, so you don't need to save again after switching languages. Messages you typed yourself are shown as-is.

The language is stored in `%USERPROFILE%\.claude\claude-notify-config.json`.

## When changes take effect

**No restart is needed.** Claude Code watches `settings.json` and reloads it into running sessions when it changes.

| Item | Takes effect | Why |
|---|---|---|
| Language, toast buttons, default message translation, project name, click-to-switch | **Next notification** | `claude-notify.ps1` runs fresh for every toast |
| Message, title, image/size, sound, display time, event on/off, conditions | **Within a few seconds of saving** | Stored in the `settings.json` hooks, which Claude Code reloads on change |

If a change still hasn't applied after a few seconds, Claude Code may have missed the file change — restart it. Older Claude Code versions only read hooks at startup and may need a restart.

## Settings window

Run `settings.bat` to open the settings window. Each event has its own tab.

### How long the notification stays

| Option | Behavior |
|---|---|
| Until dismissed | Stays on screen until you close it (default) |
| Auto-hide after ~5-7 seconds | Standard Windows behavior |

Windows toasts **do not support a custom duration in seconds** — only these two modes exist. Auto-hidden toasts remain in Notification Center (`Win`+`N`).

### When to notify

Applies to the `Notification` event only. By default all conditions are enabled; you can pick the ones you want.

| Condition | Fires when |
|---|---|
| Permission prompt | Waiting for tool approval (after ~6s) |
| Idle | No input after a response (after ~60s) |
| Authentication succeeded | Login completes |
| Background agent needs input / completed | Subagent events |
| MCP input form waiting | An MCP server asks for input |
| Auto-resumed after usage limit | Work resumes automatically after a limit lifts |

Because of the ~6s delay, approving a permission prompt before then means no toast is shown.

`Stop` has no conditions. It fires every time Claude finishes a response.

### Image / size

Choose one of three sizes.

| Option | Look | Saved option |
|---|---|---|
| Large (banner) | Image spans the full width at the top | `-Hero` |
| Small (icon) | Small icon on the left | `-Logo` (`-LogoCircle` when Circle is checked) |
| Text only | No image, smallest | none |

Windows toasts **cannot be sized in pixels.** The width is fixed by the system; only the height changes with the image layout.

Banner and icon are **set separately**, because their aspect ratios differ and sharing one image would crop or stretch it.

| Use | Ratio | Recommended | Minimum |
|---|---|---|---|
| Banner (large) | ~2:1 | **364×180** | — |
| Icon (small) | **1:1 square** | **256×256** | 64×64 |

The icon is displayed at about 48×48, but a larger source looks better on high-DPI displays. Circle crop (`-LogoCircle`) cuts the corners, so leave some margin around the edges.

Paths must be **absolute**. A relative path or a missing file makes Windows silently drop the whole toast.

### Telling VS Code windows apart / click to switch

Even with several VS Code windows open, you can tell where a toast came from.

- **The project folder name is shown in the title** — e.g. `Claude Code · Clawd_Notify`
- **Clicking the toast brings that VS Code window to the front**, restoring it if minimized.
- If the window has been closed, the folder is reopened in VS Code.

How it works: the project path from the hook (`CLAUDE_PROJECT_DIR`, or `cwd` from stdin) is embedded in the toast. Clicking it runs `claude-notify-focus.exe` via the `clawd-focus://` protocol, which finds **the VS Code window whose title contains the folder name** and brings it forward.

`claude-notify-focus.exe` is compiled at install time with PowerShell's built-in C# compiler (`Add-Type`). A PowerShell script would briefly flash a console window, so a console-less program is used instead.

- Click-to-switch is enabled only when Claude Code runs in the VS Code extension or the VS Code integrated terminal.
- If you changed VS Code's `window.title` so the folder name (`${rootName}`) is not in the title, the window cannot be found.
- If several windows share the same folder name, one of them is chosen.

### Open settings from a toast

Click the **Settings** button at the bottom of a toast to open the same window as `settings.bat`, without a console window.

### Choosing a monitor

**Not possible.** Toasts always appear on the primary monitor. The Windows toast API has no position or monitor option, and the Windows shell draws the toast.

To change it, set a different primary monitor in Windows Settings → System → Display.

### Window focus

Toasts appear **even when VS Code or the terminal is active.** Hooks fire regardless of window focus.

### Other options

- **Message / title** — set per event
- **Sound** — Default / Instant message / Mail / Alarm / Silent, etc. Alarm and Call can loop
- **Enable this notification** — uncheck to disable that event only

Use **Send a test notification** to preview the result before saving.

## What gets installed

```
%USERPROFILE%\.claude\
├── settings.json                  (only the hooks entry is added — other settings are kept)
├── claude-notify.ps1              toast script
├── claude-notify-settings.ps1     settings UI
├── claude-notify-focus.exe        switches VS Code windows on click (compiled at install)
├── claude-notify-config.json      display language
└── assets\
    ├── clawd-ask-hero.png     banner 364x180
    ├── clawd-done-hero.png    banner 364x180
    ├── clawd_question.png     icon 256x256
    ├── clawd_done.png         icon 256x256
    └── clawd.png              notification header icon 256x256 (no badge)

HKEY_CURRENT_USER\Software\Classes\clawd-focus   (protocol for toast clicks — removed on uninstall)
```

`settings.json` is backed up to `settings.json.<date>-<time>.bak` before changes. Existing settings such as `model`, `permissions`, and other hooks are preserved.

## Requirements

Windows 10 or later and Windows PowerShell 5.1 (built into Windows). No external modules.

## Troubleshooting

**1. Has it been a few seconds since you changed the settings?**
Hooks reload automatically, but a change can occasionally be missed. Restart Claude Code in that case.

**2. `Notification` does not fire while you are looking at the terminal.**
Claude Code doesn't repeat what is already on screen. Switch to another app before testing.

**3. Manual test**

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\claude-notify.ps1" -Message "Test"
```

If this works but the hook doesn't, it's a settings issue. If this doesn't work either, check Windows notification settings (Focus Assist / Do Not Disturb).

**4. Windows notification settings**
In Settings → System → Notifications, make sure "Clawd Notify" is turned on.

## Development

The distributable is the single file `Install-ClawdNotify.ps1`; the settings UI and images are embedded in it as Base64. The settings UI source is kept separately.

| File | Description |
|---|---|
| `src/claude-notify-settings.ps1` | Settings UI source |
| `build.ps1` | Embeds the sources in `src/` into `Install-ClawdNotify.ps1` |

Always build after editing the settings UI:

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

The toast script (`$NotifyScriptBody`) and the window switcher (`$FocusSource`) are plain text inside `Install-ClawdNotify.ps1` and can be edited directly.

Save `.ps1` files as **UTF-8 with BOM**. Without a BOM, Windows PowerShell 5.1 garbles Korean text.

## Notes

Toasts are sent with a dedicated AppUserModelId (`ClawdNotify`). Windows silently drops toasts from unregistered IDs, so the installer registers a display name ("Clawd Notify") and icon under `HKCU:\Software\Classes\AppUserModelId\ClawdNotify`. The toast header, notification settings, and Notification Center therefore show "Clawd Notify", and it can be turned on or off separately from other PowerShell scripts. Uninstalling removes this registration, the notification settings key (`...\Notifications\Settings\ClawdNotify`), and any toasts left in Notification Center.

---

v1.2.0 | Developer: Kim Sulho | jeremywrightkim@gmail.com
