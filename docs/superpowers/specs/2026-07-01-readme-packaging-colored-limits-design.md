# README, Packaging, and Colored Limits Design

## Goal

Make LimitDude easier to understand, install, and read at a glance.

## Scope

This release covers three user-facing improvements:

- Replace the minimal README with a polished project page that explains what LimitDude does and shows screenshots of the character overlays.
- Add a local macOS app packaging flow that builds an installable `LimitDude.app` bundle and a zip archive.
- Color Codex remaining-limit percentages in the overlay so low remaining capacity is visually distinct from healthy capacity.

## Current State

LimitDude is a Swift Package with an AppKit executable. The app already reads Codex rate limits through the Codex app-server protocol, watches recent Codex tasks, and shows a pixel character overlay for warnings and completed tasks. The current README only lists basic build/run/check commands. There is no app bundle script, and the limit overlay renders all text in one black style.

## README

The README should act as a small product page for the repository:

- Use `LimitDude` as the title and explain it as a tiny macOS menu bar companion for Codex limits and task completion signals.
- Show screenshots from `docs/assets/` near the top.
- Explain the main capabilities: menu bar status, Codex limit checks, warning overlay, task-completion overlay, long-task filtering, last-task duration, and manual simulation actions.
- Include install instructions for the generated app bundle and developer commands for building from source.
- Keep copy concise and practical, with no marketing fluff.

## Screenshots

Store screenshots under `docs/assets/` and reference them with relative Markdown image links. The first set should use the provided overlay screenshots:

- `docs/assets/limitdude-available.png`
- `docs/assets/limitdude-limits.png`

These assets are documentation files, not runtime dependencies.

## Packaging

Add `scripts/build-app.sh`.

The script must:

- Build `LimitDude` in release mode.
- Create `dist/LimitDude.app` with standard macOS bundle structure.
- Generate `Contents/Info.plist`.
- Copy the release executable to `Contents/MacOS/LimitDude`.
- Create `dist/LimitDude.zip` from the app bundle.
- Print the app and zip paths on success.

The app does not need signing or notarization in this release. The README must clearly say it is a local unsigned build and macOS may ask the user to allow it in Privacy & Security.

## Colored Percentages

The visible limit text currently looks like `Left: 5h 4%, weekly 56%`. Percentages in this remaining-capacity text should be colored by how much remains:

- `0...20%` remaining: red.
- `21...50%` remaining: yellow.
- `51...100%` remaining: green.

Only percentages in Codex limit lines need special coloring. Other bubbles can keep the existing black text style.

The implementation should keep the existing `LimitReading.reason` format and parse the display string inside the overlay drawing layer. This avoids changing the rate-limit provider contract.

## Verification

Run:

```bash
swift run LimitDudeCoreChecks
swift build
scripts/build-app.sh
```

Manual smoke test:

```bash
open dist/LimitDude.app
```

Then use menu actions such as `Show Current Limits`, `Simulate Task Done`, and `Simulate 80% Warning`.
