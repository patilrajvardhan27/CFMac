# cfmac

A free, native SwiftUI maintenance app for macOS: **Clean, Apps, Optimize, Analyze and
Status**, a menu bar panel with an animated runner, and fan control. It follows the product
described in [`../README.md`](../README.md) ("Fresh").

Copyright © 2026 cfmac contributors. All rights reserved. cfmac is free to use and share under
its [Terms of Use and License](TERMS.md). It is provided as is, **at your own risk**. Third-party
artwork is credited in [NOTICES.md](NOTICES.md).

## Requirements

- macOS 14 or later on Apple silicon
- Xcode Command Line Tools (`xcode-select --install`); full Xcode is not required
- Network access for the first build, to download the licensed artwork
- Optional: Homebrew and `mas` for the Updates segment

## Build, run and test

```bash
cd cfmac
./scripts/build-app.sh       # fetches artwork, builds, signs → build/cfmac.app
open build/cfmac.app
./scripts/test.sh            # unit tests (Swift Testing)
```

`scripts/fetch-artwork.sh` downloads the textures and runner frames from their upstream sources
into `Artwork/` and checks every file against a pinned SHA-256. `scripts/test.sh` adds the Swift
Testing plugin paths that SwiftPM omits when only the Command Line Tools are installed.

For a development run without bundling, point cfmac at the package folder so it finds the
artwork and legal documents:

```bash
swift build && CFMAC_RESOURCES_DIR=$PWD .build/debug/cfmac
```

On first launch cfmac shows a welcome sheet. You must accept the Terms of Use before using it.
For the most thorough cleaning, grant **Full Disk Access** to `cfmac.app` in System Settings ›
Privacy & Security.

## Features

| Area              | What it does                                                                                                                                                                                                                                                                                                                                                                                                    |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Clean**         | Scans known cache, log, developer, browser, chat, AI, cloud and leftover locations, plus every app's Chromium and Electron caches. You review each section, items are marked Safe, Review or Look Up, and you can choose _Never Clean This_. Large data that is unsafe to bulk-delete (device backups, local AI models, Docker's disk, simulators) gets a **Look Up** button that opens a web search for the safe way to free it. If an app is using an item, cfmac offers to quit it. Items go to the Trash by default                                                                               |
| **Apps**          | _Uninstall_ removes apps with their leftover data (Auto/Review matches) or clears data only. _Updates_ uses Homebrew and the App Store, and can also uninstall any listed package or app (casks optionally with their data). _Startup_ lists background services you can enable, disable or trash                                                                                                                                                                                                    |
| **Optimize**      | Rebuilds QuickLook, clears old window states, removes broken agents, repairs corrupted preferences and clears quarantine history. Flushing DNS, purging memory and periodic maintenance run as admin behind one password prompt. Glitch fixes restart stuck system UI                                                                                                                                           |
| **Analyze**       | Drills into the whole disk with a squarified treemap, breadcrumbs, _This Folder_ / _Largest Files_ views, and Move to Trash                                                                                                                                                                                                                                                                                     |
| **Status**        | Health score, per-core CPU and CPU/GPU temperatures, memory pressure, battery health, free space, network, and a **Fan** card (Auto / Cool / Max). The process table supports Terminate and Force Quit                                                                                                                                                                                                          |
| **Menu bar**      | A runner animal (17 to pick from, faster when the CPU is busier) with a live metric. Change it from the panel or the logo in the app's tab bar. The panel shows stats, top processes, fan mode, Awake, Clean Screen, Eject and lifetime totals                                                                                                                                                                                                                                            |
| **Tools**         | Keep Screen On (three modes), Clean Screen (hold Esc to exit), Doctor report, low-disk alert                                                                                                                                                                                                                                                                                                                    |
| **Personalize**   | Light, dark or system appearance; a color per tab; the macOS accent color; a planet per screen (Earth, Moon, Mercury, Venus, Mars, Jupiter, Saturn with rings, Uranus, Neptune, Sun) and its spin speed; Reduce Motion; reorder or hide Status cards; seven menu bar runners that speed up with CPU, GPU, network or fan activity; up to three live numbers in the menu bar                                     |
| **Clean presets** | Recommended, Light weekly, Developer deep clean, Everything or None, your own folders to review, and automatic cleaning (daily, weekly, monthly or when free space is low) that only moves Safe items to the Trash. Put Back undoes the last clean                                                                                                                                                              |
| **Watchlist**     | Get notified, or have cfmac quit an app, when it uses too much CPU or memory for too long. Right-click a process in Status › Watch This Process                                                                                                                                                                                                                                                                 |
| **Keyboard**      | ⌘K command palette for every action, and global shortcuts you record yourself (no special permissions needed)                                                                                                                                                                                                                                                                                                   |
| **Share stats**   | A card with your lifetime space freed and milestones, copied or saved as an image. It holds only those totals                                                                                                                                                                                                                                                                                                   |
| **Done sounds**   | A sound plays when cleaning, maintenance, an uninstall or an update finishes: 🔔 Chime, 🎉 Ta-da, 🍯 "Honeyyy, it's doneee!", 🥤 Burp, 💨 Fart, 🌬️ Wind swoosh, 🚽 Flush, 🫧 Bubble pop, 🎲 Surprise me, or 🔕 Silent, plus your own imported sound files or a line you type for a voice to say. Choose one for everything or one per job, with quiet hours and a "only when cfmac is in the background" option |

Shortcuts: ⌘1–⌘5 switch tabs, ⌘[ / ⌘] move between tabs, ⌘F searches Apps, and ⌃⌥⌘L starts
Clean Screen.

## Done sounds

Every sound except the voice is synthesized in code, so cfmac ships no audio files and no
third-party recordings. The burp is a glottal buzz shaped by vowel formants, the fart is a
wobbling pulse wave that sputters out, the flush combines a lever clunk, rushing water, gurgles
and a draining swirl, and the swoosh is filtered noise sweeping up and down. "Honeyyy, it's
doneee!" uses the macOS speech voice (Samantha when installed) with drawn-out SSML prosody.

To listen to them outside the app:

```bash
swift run -c release cfmac-tools sounds build/sounds && open build/sounds
```

## Fan control

Fan control is **off until you turn it on** (Status › Fan › Turn on fan control, or Settings ›
Fan). Reading fan speed and chip temperatures needs no privileges; only changing speed does.

- **Turning it on** lists every change, then asks for your password once. It installs
  `cfmac-helper` at `/Library/PrivilegedHelperTools/app.cfmac.helper` with
  `/Library/LaunchDaemons/app.cfmac.helper.plist`. Cool and Max work only after that.
- **Scope:** the helper only reads fans and sets their speed. Its socket
  (`/var/run/app.cfmac.helper.sock`) belongs to your account with mode 0600, and the helper
  checks the caller's user ID on every request. Requests are one-line JSON, limited in size and time.
- **Safety:** speeds stay between each fan's own minimum and maximum. The helper saves the
  fans' original mode and restores exactly that when you choose Auto, quit cfmac, turn fan
  control off, or when cfmac fails to renew its **20-second lease** (for example, after a crash).
  cfmac renews the lease from its own background loop, so Cool and Max hold with any tab open,
  from the menu bar, or with the window closed. If the helper itself stops unexpectedly, it saves
  the original fan state first and restores it when launchd starts it again.
- **Updating cfmac** ships a new helper. The first time you pick Cool or Max afterwards, cfmac asks
  once to update it.
- **Your curve:** drag the points of the Cool curve in Settings › Fan. Quiet hours cap Cool's
  speed at night, and app rules raise the mode while an app runs (for example, Cool while Xcode
  builds).
- **Turning it off** returns the fans to macOS and deletes the helper and its launch file.

Fan writes need root, so they were not exercised during development. Try Cool once and check
that the RPM changes on your Mac.

## Privacy and security

- **Names and sizes only.** cfmac reads file names, sizes, dates and types. It never opens your
  documents. The only file contents it reads are a sound file you pick to import.
- **Personal data stays off limits.** `PrivacyGuard` keeps cfmac out of Photos libraries, Mail,
  Messages, Contacts, Calendars, Safari, Keychains, cookies and Apple apps' private containers,
  even with Full Disk Access. Analyze shows them as "Private · not scanned"; they cannot be
  cleaned or removed.
- **No sensitive permissions.** No camera, microphone, location, contacts, photos or Focus
  access. Global shortcuts use Carbon hot keys, which need no Accessibility permission.
- **Offline by default.** cfmac never contacts the internet on its own. Updates are checked only
  when you click Check Now, through Homebrew or `mas`. **Look Up** opens a search page in your
  browser only when you click it, and the query holds only the item's name. A unit test fails the
  build if networking APIs, personal-data frameworks or any web link other than that search page
  appear in the sources.
- **Local data only.** Preferences, stats, imported sounds (copied into an owner-only folder)
  and the last automatic clean's undo list stay in your user Library; Settings › Privacy erases
  them.
- **Hardening.** Every removal passes `SafetyGuard`. Admin scripts are written with
  `O_EXCL | O_NOFOLLOW` and mode 0600 and deleted after use. The app and helper are signed with
  the hardened runtime.

## Size and performance

Measured on an M4 MacBook Pro:

|                                  |                                                                                      |
| -------------------------------- | ------------------------------------------------------------------------------------ |
| App bundle                       | 10 MB (artwork 1.5 MB: textures are stored at 1024 px, enough for how they're shown) |
| DMG                              | 4.1 MB                                                                               |
| Idle, window open, animations on | about 11% CPU, 122 MB memory                                                         |
| Idle with Reduce Motion          | about 0–1% CPU                                                                       |

Only one 3D planet view renders per screen, and planet scenes rebuild only when you pick a
different planet. The Analyze folder cache is capped at 24 levels, and rendered sounds at three.
Clean groups and totals are built in one pass when results change, and Watchlist checks are
linear in the number of processes.

## Architecture

```
Sources/
├── SMCKit/        SMC connection, key/value codec, fan reading and control, chip temperatures
├── FanService/    helper wire protocol, fan curve, socket framing, install/uninstall scripts
├── CfmacCore/     engines with no UI: privacy and safety guards, file operations, clean catalog and engine,
│                  app inventory, updates, startup items, optimize tasks, disk scanner,
│                  treemap, system metrics, health score, Markdown blocks, presets, schedules,
│                  watchlist rules, fuzzy search, key combos
├── Artwork/       artwork lookup, SceneKit planet scenes, runner frames
├── SoundKit/      completion sounds: oscillator/noise/filter synthesis, WAV encoding, voice line
├── cfmac/         SwiftUI app: one folder per screen, settings, fan controller, menu bar
│                  status item, tools, About/Terms/Licenses
├── cfmac-helper/  root daemon: socket server and lease-supervised fan control
└── cfmac-tools/   build tool: app icon set, planet previews, sound export
Tests/             CfmacCoreTests, FanServiceTests, ArtworkTests, SoundKitTests
```

Design rules:

- **One owner per resource.** `SystemMonitor` owns live metrics, `FanController` owns fan state,
  `AppSettings` owns every preference key, and `SafetyGuard` gates every removal.
- **Engines are pure where possible** and take explicit inputs (such as the protected-path set),
  so they're testable without the UI.
- **Swift 6 language mode** with strict concurrency. UI models are `@MainActor`, and blocking
  work runs in detached tasks with `Sendable` inputs.
- **Menu bar via `NSStatusItem`.** Animating a SwiftUI `MenuBarExtra` label rebuilds every scene
  and the main menu on each frame.
- **`@Local` instead of `@State`.** SwiftUI's `@State` macro needs a compiler plugin that ships
  only with full Xcode. `@Local` (`Shared/Local.swift`) is an equivalent wrapper built on
  `StateObject`.
- Formatting follows `.swift-format`; `swift format lint -r Sources Tests` reports no issues.

## Not included

Battery charge limiting, Wi-Fi low-latency mode, the AI tool sub-screen, "Why is this running?",
localization and automatic app updates. Recording a voice clip and taking colors from your
wallpaper were left out on purpose: they would need microphone access or reading a personal image.
