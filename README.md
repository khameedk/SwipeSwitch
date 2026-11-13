# SwipeSwitch

[![Build](https://github.com/khameedk/SwipeSwitch/actions/workflows/build.yml/badge.svg)](https://github.com/khameedk/SwipeSwitch/actions/workflows/build.yml)
[![CodeQL](https://github.com/khameedk/SwipeSwitch/actions/workflows/codeql.yml/badge.svg)](https://github.com/khameedk/SwipeSwitch/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/khameedk/SwipeSwitch/badge)](https://scorecard.dev/viewer/?uri=github.com/khameedk/SwipeSwitch)

Switch apps and windows on your Mac with a trackpad swipe.

Swipe right with three fingers and a switcher appears with your recent apps. Keep swiping to move
through them, then lift your fingers to switch. It works like ⌘-Tab, but on the trackpad.

- **Apps or windows.** Switch between apps, or between individual windows (shown with their titles).
- **Grid or row.** In the grid, your most recent apps are on the top row; swipe down for older ones.
- **All desktops or just this one.** Include apps/windows from every desktop (Space) or only the current one.
- **Smooth and tactile.** A sliding highlight follows your fingers, with a haptic click on each step.
- **Lives in the menu bar.** Every option is in its Settings window.

## Requirements

- macOS 14 (Sonoma) or later, on an Apple Silicon Mac
- A Force Touch trackpad: any MacBook from 2015 on, or a Magic Trackpad
- Apple's Command Line Tools (free) to build it

## Install

SwipeSwitch is distributed as source code: you build it on your own Mac. That means you can read
everything it does first, and macOS doesn't block it as an app downloaded from the internet.

1. Install the Command Line Tools, if you haven't already:
   ```bash
   xcode-select --install
   ```
2. Download the code and build it:
   ```bash
   git clone https://github.com/khameedk/SwipeSwitch.git
   cd SwipeSwitch
   ./build.sh --install
   ```
   This builds `SwipeSwitch.app`, copies it to `/Applications` and opens it.
3. When asked, grant **Accessibility** access in System Settings › Privacy & Security › Accessibility.

To update later, run `git pull` and `./build.sh --install` again. Your settings and permissions are kept.

## Using it

| Gesture | What happens |
| --- | --- |
| Swipe right with three fingers | Opens the switcher with the previous app (or window) selected |
| Keep swiping right / left | Moves forward (older) / back |
| Swipe down / up (grid layout) | Moves to the next / previous row |
| Lift your fingers | Switches to the selected app or window |

**Tip:** If macOS already uses three-finger side swipes on your Mac (for "swipe between pages",
"swipe between full-screen apps" or three-finger drag), SwipeSwitch's settings show a warning and
a button to change it. You can also switch SwipeSwitch to four fingers.

## Settings

Open them from the menu bar icon › **Settings…**

| Section | Options |
| --- | --- |
| General | Enable/disable, launch at login |
| Gesture | Three or four fingers · start by swiping right or left · distance per step (mm) · haptic feedback and strength |
| Switching | Apps or windows · all desktops or current desktop · sort by last active or name · include minimized windows · include hidden apps' windows · how many items · excluded apps |
| Appearance | Grid or single row · columns · icon size · show every name · wrap around at the ends |

Apps without an open window are never shown.

## Permissions and privacy

SwipeSwitch runs entirely on your Mac. **It contains no network code**: it never connects to the
internet, and it collects, stores and sends nothing about you, your apps or your windows.

| Permission | Required? | What it's used for |
| --- | --- | --- |
| **Accessibility** | Yes | Bringing the app or window you pick to the front (including on other desktops), reading window titles and whether a window is minimized, and noticing which window you last focused so the list is in the right order. |
| **Screen Recording** | Optional | Only to read the *titles* of windows on other desktops before you've visited them. SwipeSwitch never captures, records or saves screen images. |

What else it touches:

- **Trackpad input** is read through macOS's touch framework, which needs no permission. Only finger
  positions are used, and only while a gesture is in progress.
- **Settings** are stored in macOS's normal preferences for the app (`io.github.khameedk.swipeswitch`).
- **Window titles and focus order** are kept in memory while the app runs and are never written to disk.

You can check all of this in the source: everything lives in [`Sources/`](Sources) (about 1,700 lines of Swift).

### Security checks

Every change to this repo is checked automatically on GitHub:

| Check | What it does |
| --- | --- |
| **Build** | Builds the app from exactly the code in the repo, then runs [`scripts/check-no-network.sh`](scripts/check-no-network.sh), which fails if the source contains networking code or the built app imports networking functions. |
| **CodeQL** | GitHub's code scanner looks for security problems in the Swift code (also weekly). |
| **OpenSSF Scorecard** | Rates the repo's security practices; the score is the badge at the top. |
| **Dependabot** | Keeps the GitHub Actions used above up to date. The app itself has no third-party dependencies. |

You can run the network check yourself after building:

```bash
./scripts/check-no-network.sh build/SwipeSwitch.app/Contents/MacOS/SwipeSwitch
```

These checks look for bugs and unexpected network access; they can't prove intent. The best
assurance is that the code is short and you build it yourself, so you can read exactly what you run.

### Undocumented macOS functions

Some things SwipeSwitch does have no public macOS API, so it uses private system functions, as other
window switchers do:

- reading raw trackpad touches and driving the trackpad's haptic motor (`MultitouchSupport`)
- finding windows on other desktops and telling real windows from closed ones (window-server calls)
- matching Accessibility windows to their window IDs

These are looked up at runtime, and the app falls back gracefully if one is missing. A future macOS
update could still change them, so if something stops working after an update, please open an issue.

## Troubleshooting

- **Nothing happens when I swipe.** Check the menu bar icon: "Enabled" should be ticked, and Settings
  should show a trackpad detected. Look for a gesture-conflict warning in Settings › Gesture.
- **The switcher opens but doesn't switch apps.** Grant Accessibility access (Settings › Status shows
  whether it's granted). If it's already on, remove SwipeSwitch from the Accessibility list and add it again.
- **It stopped responding after waking from sleep.** Use Settings › Status › **Restart tracking**.
- **The menu bar icon is missing** on a Mac with a notch. macOS hides icons behind the notch when the
  menu bar is crowded. Quit a few menu bar apps or use a menu bar manager.

## Uninstall

1. Menu bar icon › **Quit SwipeSwitch**, and turn off "Launch at login" first if you enabled it.
2. Delete `/Applications/SwipeSwitch.app`.
3. Remove SwipeSwitch from System Settings › Privacy & Security › Accessibility (and Screen Recording).
4. Optionally delete its settings:
   ```bash
   defaults delete io.github.khameedk.swipeswitch
   ```

## Development

```bash
./build.sh            # builds build/SwipeSwitch.app
./build.sh --install  # also installs to /Applications and opens it
```

| File | What it does |
| --- | --- |
| `MultitouchMonitor.swift` | Reads trackpad touches and drives haptics |
| `GestureRecognizer.swift` | Turns finger movement into begin / step / end |
| `AppTracker.swift` | Keeps apps in most-recently-used order |
| `WindowTracker.swift` | Finds real windows on every desktop, with titles and focus order |
| `Switcher.swift` | The switcher overlay |
| `Activator.swift` | Brings the chosen app or window to the front |
| `SettingsView.swift`, `AppDelegate.swift`, `Prefs.swift` | Settings window, menu bar menu and preferences |

**Demo mode** plays a scripted swipe so you can check the overlay without touching the trackpad:

```bash
SWIPESWITCH_DEMO=1 build/SwipeSwitch.app/Contents/MacOS/SwipeSwitch
```

Add `SWIPESWITCH_SNAPSHOT_DIR=/some/folder` to save PNG snapshots of the overlay and settings window
(SwipeSwitch's own windows only) into that folder.

## License

[MIT](LICENSE)
