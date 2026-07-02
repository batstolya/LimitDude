<div align="center">

# LimitDude

**A tiny macOS menu bar companion that watches Codex limits and tells you when Codex is ready again.**

![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-13+-111111?style=flat-square&logo=apple&logoColor=white)
![Local only](https://img.shields.io/badge/local-only-2E7D32?style=flat-square)
![No services](https://img.shields.io/badge/external_services-none-546E7A?style=flat-square)

![LimitDude shows a pixel character holding a Codex is available sign after a task finishes](docs/assets/limitdude-task-done.gif)

</div>

LimitDude lives in your menu bar, quietly watches local Codex state, and pops up only when something deserves attention: a long task finished, your limits are getting tight, or the reset happened and you can work again.

## Why It Exists

Codex work often has a small awkward gap: you start a long task, switch away, and then keep wondering whether it finished or whether you are close to a limit. LimitDude turns that into a gentle local signal instead of another thing to babysit.

## Highlights

- Watches active Codex tasks and shows **Codex is available** when a long task finishes.
- Checks current Codex rate limits from the local Codex app-server protocol.
- Shows 5-hour and weekly remaining percentages.
- Colors limit percentages red, yellow, or green so the state is scannable.
- Warns when usage is getting close to the edge.
- Detects reset/recovery moments and shows a friendly overlay.
- Ignores quick answers so the screen does not get noisy.
- Includes **Setup Status** for explaining what is missing on a new Mac.
- Runs locally and does not talk to external services.

## Demo

| Task finished | Limit warning |
| --- | --- |
| ![LimitDude task done overlay animation](docs/assets/limitdude-task-done.gif) | ![LimitDude warning overlay animation with remaining limit percentages](docs/assets/limitdude-limits.gif) |

The README animations are rendered from the same `PixelDudeView` code used by the app, so the GIFs stay in sync with the real overlay.

## Install Locally

Build the macOS app bundle:

```bash
scripts/build-app.sh
```

Open the build output:

```bash
open dist
```

Then drag `LimitDude.app` into `/Applications`, or run it directly from `dist/`.

LimitDude is currently an unsigned local build. The first launch may require approval in **System Settings -> Privacy & Security**.

## Developer Commands

Build the Swift package:

```bash
swift build
```

Run from source:

```bash
swift run LimitDude
```

Run core checks:

```bash
swift run LimitDudeCoreChecks
```

Check Codex limits once:

```bash
swift run LimitDudeCodexCheck
```

Show a task-done overlay demo:

```bash
swift run LimitDude --demo-task-done
```

Show a warning overlay demo:

```bash
swift run LimitDude --demo-warning --demo-click
```

Regenerate README GIF assets:

```bash
swift run LimitDude --render-readme-assets
```

## How It Works

LimitDude uses a small Swift Package with three main pieces:

- `LimitDudeCore` models limit readings, reset/recovery detection, and task completion filtering.
- `LimitDudeMac` reads local Codex app and task state from macOS.
- `LimitDude` owns the menu bar app, overlay window, demo modes, and README asset renderer.

The overlay is a borderless AppKit window drawn by `PixelDudeView`. It has the same entrance, idle, warning, detail, and task-done animation whether it appears in the app or in the generated README GIFs.

## Local State

LimitDude expects Codex.app to be installed at:

```text
/Applications/Codex.app
```

The task watcher reads local Codex state from:

```text
~/.codex/state_5.sqlite
```

No external services are used by LimitDude itself.

## Troubleshooting

If the menu bar item appears but no useful status shows up, open **Setup Status** from the LimitDude menu. It checks whether Codex is installed where LimitDude expects it and whether the local Codex state file is available.

If macOS blocks launch, open **System Settings -> Privacy & Security** and allow the unsigned app build.
