# README, Packaging, and Colored Limits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make LimitDude readable, presentable on GitHub, and locally installable as a macOS app bundle.

**Architecture:** Keep Codex provider output unchanged and add display-only parsing in the AppKit overlay for colored remaining percentages. Add documentation assets under `docs/assets/`. Add a shell packaging script that wraps the release Swift executable into `dist/LimitDude.app` and `dist/LimitDude.zip`.

**Tech Stack:** Swift 6, Swift Package Manager, AppKit, POSIX shell, Markdown.

## Global Constraints

- Platform remains macOS 13 or newer.
- Do not add third-party dependencies.
- The local app bundle is unsigned and not notarized in this release.
- Remaining percentages use `0...20%` red, `21...50%` yellow, and `51...100%` green.
- Documentation screenshots live under `docs/assets/`.

---

### Task 1: Colored Remaining Percentages

**Files:**
- Modify: `Sources/LimitDude/PixelDudeOverlay.swift`

**Interfaces:**
- Consumes: `PixelDudeMode.detailText` and existing `drawBubble(origin:text:width:height:)`.
- Produces: colored rendering for percentage tokens in Codex limit detail bubbles.

- [ ] Add a helper that detects integer percentage tokens in limit text.
- [ ] Add a helper that maps remaining percent values to red/yellow/green `NSColor`.
- [ ] Update `drawBubble` to use attributed drawing when text contains Codex limit percentages.
- [ ] Verify with `swift build`.

### Task 2: README and Screenshots

**Files:**
- Create: `docs/assets/limitdude-available.png`
- Create: `docs/assets/limitdude-limits.png`
- Modify: `README.md`

**Interfaces:**
- Consumes: provided screenshot files from the current Codex message and previous overlay screenshot.
- Produces: a README with screenshot links and practical install/build usage.

- [ ] Copy screenshots into `docs/assets/`.
- [ ] Replace README with sections: overview, screenshots, capabilities, install, developer commands, notes.
- [ ] Verify image links point to existing files.

### Task 3: macOS App Bundle Packaging

**Files:**
- Create: `scripts/build-app.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: SwiftPM release build output at `.build/release/LimitDude`.
- Produces: `dist/LimitDude.app` and `dist/LimitDude.zip`.

- [ ] Add `dist/` to `.gitignore`.
- [ ] Add an executable script that builds release, creates bundle folders, writes `Info.plist`, copies the executable, and zips the app.
- [ ] Run `scripts/build-app.sh`.
- [ ] Verify `dist/LimitDude.app/Contents/MacOS/LimitDude` exists and is executable.

### Task 4: Final Verification

**Files:**
- Verify all changed files.

**Interfaces:**
- Consumes: completed tasks 1-3.
- Produces: pushed GitHub commit with the mini-release.

- [ ] Run `swift run LimitDudeCoreChecks`.
- [ ] Run `swift build`.
- [ ] Run `scripts/build-app.sh`.
- [ ] Inspect `git diff`.
- [ ] Commit and push.
