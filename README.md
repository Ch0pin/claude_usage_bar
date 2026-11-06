# Claude Usage Bar

An unofficial native macOS menu-bar app that shows how much of your Claude plan's usage is left as a small gauge, without opening the usage page.

![macOS](https://img.shields.io/badge/macOS-13%2B-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)

## What it shows

The menu bar shows a gauge of **how much is left**, plus an optional percentage, for example `━━━━━── 88%`. Pick one of three styles in the panel:

- **Bar** (default): a capsule progress bar
- **Segments**: eight blocks, like a level meter
- **Ring**: a circular gauge

The gauge is monochrome while usage is normal and adapts to light and dark menu bars. It turns **orange** at 25% or less remaining and **red** at 10% or less. If your plan has both a 5-hour session window and a weekly limit, a **split** mode shows both: two bars, two rows of segments, or two concentric rings.

Click it to open a panel with:

- Current session (5-hour) usage and its reset countdown, if your plan has a session window
- Weekly usage across all models and its reset countdown
- Per-model weekly limits, when your plan has them
- Extra-usage spend, when enabled
- Settings: gauge style, which limit the gauge tracks (only when your plan has more than one), whether to show the percentage, and launch at login

Only limits that Claude reports for your account are shown. For example, if your plan has no 5-hour window, the app shows nothing for it.

Usage refreshes every five minutes, when you open the panel and the data is more than a minute old, after the Mac wakes, and when you click refresh.

## Requirements

- macOS 13 or newer
- Apple Command Line Tools or Xcode
- [Claude Code](https://claude.com/claude-code) installed and signed in with a Claude subscription (Pro, Max, Team, or Enterprise)

## Build and run

```sh
./scripts/build_app.sh
open dist/ClaudeUsageBar.app
```

To check the live data path from a terminal:

```sh
dist/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar --check
```

The check prints only the plan name, percentages, and reset times. It never prints credentials.

The build script picks an SDK that matches the host macOS major version. Set `CLAUDE_USAGE_BAR_SDKROOT=/path/to/MacOSX.sdk` to override it.

## Install

Drag `dist/ClaudeUsageBar.app` into `/Applications`, launch it, and turn on **Launch at login** in its panel. You can also add it under **System Settings → General → Login Items**.

## How it works

The app reads Claude Code's existing sign-in. It looks first in the macOS Keychain item `Claude Code-credentials`, reading it through `/usr/bin/security` (the same tool Claude Code uses, so no extra Keychain prompts appear). If that isn't available, it falls back to `~/.claude/.credentials.json`. It then calls `GET https://api.anthropic.com/api/oauth/usage`, the same endpoint behind Claude Code's `/usage` command.

- The access token is used only in the request header. It is never logged, cached, or written to disk. Only the derived percentages are cached so the bar has a value at launch.
- The app never refreshes or rewrites Claude Code's tokens itself. When the token has expired, it runs `claude auth status` (which uses no model quota) so Claude Code can refresh its own sign-in, then retries once.

## Troubleshooting

- **"No Claude Code sign-in found":** install Claude Code and run `claude` to sign in.
- **"Your sign-in has expired":** run `claude` once in a terminal, then click refresh.
- **Claude Code isn't found for the token refresh:** set `CLAUDE_USAGE_BAR_CLAUDE_PATH` to the `claude` executable. The app checks `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, and `PATH`.
- **Stale values:** the last successful reading stays visible, and the refresh error appears below it.
- **Previewing the gauge styles:** `ClaudeUsageBar --render-gauge-preview out.png` renders every style and state on light and dark menu bars.

## Compatibility and project status

The OAuth usage endpoint is undocumented and may change without notice. This project is unofficial and is not affiliated with or endorsed by Anthropic. Usage limits are reported only for Claude subscription plans, not API-key billing.

The generated app is ad-hoc signed for local use.
