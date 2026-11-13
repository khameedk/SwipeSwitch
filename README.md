# SwipeSwitch

[![Build](https://github.com/khameedk/SwipeSwitch/actions/workflows/build.yml/badge.svg)](https://github.com/khameedk/SwipeSwitch/actions/workflows/build.yml)
[![CodeQL](https://github.com/khameedk/SwipeSwitch/actions/workflows/codeql.yml/badge.svg)](https://github.com/khameedk/SwipeSwitch/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/khameedk/SwipeSwitch/badge)](https://scorecard.dev/viewer/?uri=github.com/khameedk/SwipeSwitch)

Switch apps and windows on your Mac with a trackpad swipe.

Swipe right with three fingers and a switcher appears with your recent apps. Keep swiping to move
through them, then lift your fingers to switch. It works like ⌘-Tab, but on the trackpad.

<p align="center">
  <img src="docs/images/swipeswitch-demo-93120264.gif" width="720"
       alt="Animation on a mock desktop: three fingers swipe right on a trackpad, a frosted SwipeSwitch overlay appears over a Safari window showing a grid of windows, each with its app icon and title, the highlight moves right to 'Project ideas', on to 'Library', then back to 'Project ideas', and lifting the fingers brings that Notes window to the front.">
</p>
<p align="center"><sub>Illustration on a mock desktop: window contents are made up; app icons are macOS's own.</sub></p>

- **Apps or windows.** Switch between apps, or between individual windows (shown with their titles).
- **Grid or row.** In the grid, your most recent apps are on the top row; swipe down for older ones.
- **All desktops or just this one.** Include apps/windows from every desktop (Space) or only the current one.
- **Smooth and tactile.** A sliding highlight follows your fingers, with a haptic click on each step.
- **Or use the keyboard.** Optionally open the same switcher with ⌘Tab, in place of macOS's own.
- **Lives in the menu bar.** Every option is in its Settings window.

## Requirements

- macOS 14 (Sonoma) or later, on an Apple Silicon Mac
- A Force Touch trackpad: any MacBook from 2015 on, or a Magic Trackpad
- Apple's Command Line Tools (free) to build it

## Install

### Option 1: Homebrew

```bash
brew trust --tap khameedk/tap
brew install --cask khameedk/tap/swipeswitch
```

Homebrew asks you to trust taps from outside its own catalogue before installing from them; the
`brew trust` line trusts this tap, which only contains SwipeSwitch (undo with `brew untrust --tap khameedk/tap`). Then follow steps 2 and 3 below (Open Anyway, Accessibility). Update
with `brew upgrade --cask swipeswitch`.

### Option 2: Download

1. Download the latest **SwipeSwitch-vX.Y.Z.zip** from [Releases](https://github.com/khameedk/SwipeSwitch/releases/latest),
   unzip it, and move **SwipeSwitch.app** to Applications.
2. Open it. SwipeSwitch isn't notarized by Apple (that needs a paid developer account), so macOS blocks the
   first launch: go to **System Settings › Privacy & Security**, scroll down, and click **Open Anyway**.
3. When asked, grant **Accessibility** access in System Settings › Privacy & Security › Accessibility.

Each release is built on GitHub from the tagged source and comes with a signed build record, so you can
check the download came from this repository (needs the [GitHub CLI](https://cli.github.com)):

```bash
gh attestation verify SwipeSwitch-vX.Y.Z.zip --repo khameedk/SwipeSwitch
```

To update, download the newest release and replace the app. Your settings and permissions are kept.

### Option 3: Build from source

Build it on your own Mac, so you can read everything it does first and macOS doesn't block it as a download.

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
| Press Esc | Cancels: the switcher closes and lifting your fingers won't switch |

**Keyboard (optional):** turn on Settings › Keyboard › **Open with ⌘Tab** to use the same switcher from
the keyboard, in place of macOS's own app switcher:

| Keys | What happens |
| --- | --- |
| ⌘Tab | Opens the switcher with the next app (or window) selected (⌘⇧Tab starts at the last) |
| Tab (⌘ held) | Moves forward |
| Shift (⌘ held) | Moves back one; holding Shift and tapping Tab keeps moving back |
| ← → ↑ ↓ (⌘ held) | Moves left / right, or between rows in the grid |
| Esc / Return | Cancels / switches right away |
| Release ⌘ | Switches to the selected app or window |

Only one app can own ⌘Tab: if you use another switcher on ⌘Tab (such as AltTab), quit it or change its
shortcut. SwipeSwitch gives ⌘Tab back to macOS when you turn the option off or quit.

**Windows mode** shows each window on its own, with its title, so two browser windows appear separately:

<p align="center">
  <img src="docs/images/windows-mode-379511cb.png" width="720"
       alt="The SwipeSwitch overlay in windows mode over a mock Safari window: a row of window tiles, each with an app icon and a window title such as 'Inbox (3)' or 'Trip planning', with one tile highlighted.">
</p>

## Gesture conflicts

SwipeSwitch uses three-finger swipes: **right** to open the switcher, then **left, right, up and down**
to move around while it's open. Anything else on your Mac that responds to three-finger swipes can fire
at the same time. Check these before you start:

- **macOS's own gestures** (System Settings › Trackpad › More Gestures, and Accessibility › Pointer
  Control › Trackpad Options):
  - *Swipe between pages* or *Swipe between full-screen applications* set to three fingers clash with
    the side swipes. SwipeSwitch's Settings warns about these and has a button to open Trackpad settings.
  - *Three-finger drag* clashes with every swipe (it drags windows instead). Settings warns about it too.
  - *Mission Control* or *App Exposé* set to three-finger swipe up/down clash with moving between rows in
    the grid. Settings doesn't detect this one, so check it yourself, or use the single-row layout.
- **Other gesture apps** such as BetterTouchTool see every touch too. macOS gives each app its own copy of
  the trackpad input, so SwipeSwitch **can't block** another app from reacting. For BetterTouchTool, see
  [Using it with BetterTouchTool](#using-it-with-bettertouchtool).
- **The first few millimetres** of a swipe happen before the switcher opens, so a gesture another app
  recognizes that early can't be paused, even with the BetterTouchTool setup. Lowering
  *Swipe distance to open* narrows that window.

If three-finger swipes are taken, switch SwipeSwitch to **four fingers** (Settings › Gesture). macOS
uses four-finger swipes for desktops and Mission Control by default, so turn those off first.

## Settings

Open them from the menu bar icon › **Settings…**

| Section | Options |
| --- | --- |
| General | Enable/disable, launch at login |
| Keyboard | Open with ⌘Tab (off by default) |
| Gesture | Three or four fingers · start by swiping right or left · distance to open and distance per step (mm) · haptic feedback and strength |
| Switching | Apps or windows · all desktops or current desktop · sort by last active or name · include minimized windows · include hidden apps' windows · how many items · excluded apps |
| Appearance | Grid or single row · columns · icon size · show every name · wrap around at the ends |
| BetterTouchTool | Tell BTT while the switcher is open (off by default) · optional shared secret · see [Using it with BetterTouchTool](#using-it-with-bettertouchtool) |

Apps without an open window are never shown.

### Using it with BetterTouchTool

macOS sends every trackpad touch to every app that listens, so BetterTouchTool sees your SwipeSwitch
swipes too. While the switcher is open you move with three-finger swipes left, right, up and down, so
BTT may also run any **three-finger swipe** gestures you have set up (for example, swiping back left
could also trigger a BTT "3 Finger Swipe Left" shortcut in the app you're in). SwipeSwitch can't block
another app's trackpad input, but it can tell BTT when the switcher is open so BTT skips those gestures.

**1. In SwipeSwitch:** Settings › BetterTouchTool › turn on **Tell BetterTouchTool while the switcher
is open**. SwipeSwitch then sets the BTT variable `swipeswitch_active` to `1` while the switcher is open
and `0` when it closes, using BTT's [`btt://` links](https://docs.folivora.ai/docs/scripting/url-scheme/).

**2. In BTT, allow the links:** Settings › Scripting BTT › turn on **Allow external BetterTouchTool
Scripting**. We recommend also setting a **shared secret** there (otherwise any app or web page can send
BTT commands); enter the same secret in SwipeSwitch › Settings › BetterTouchTool. BTT may ask once
whether to allow the links.

**3. In BTT, add a condition to each three-finger swipe gesture.** This covers every
**3 Finger Swipe Left, Right, Up or Down** you have, both under **For All Apps** and in each app's own
settings (for example, an app-specific "3 Finger Swipe Left"). For each one:

1. In BTT's configuration window, select **For All Apps** or the app in the left list.
2. Click the gesture.
3. In the gesture's settings on the right, open **Advanced Conditions…**.
4. Add one condition: variable `swipeswitch_active`, **is not**, value `1`. Save.

BTT's **Search All Triggers** button (below the app list) can help you find them all. This uses BTT's
[Advanced Trigger Conditions](https://docs.folivora.ai/docs/actions/conditions/): BTT still notices the
swipe, but skips its action while the switcher is open. Outside the switcher, the gesture works exactly as
before.

**4. Check it.** With an app in front that has one of these gestures, swipe right with three fingers to
open the switcher, swipe back left, then lift your fingers: the BTT action should **not** run. A plain
three-finger swipe left, without the switcher, should still run it.

Notes:

- SwipeSwitch only sends these links while BTT is already running (a `btt://` link would otherwise launch
  it), and it resets the variable to `0` when it starts and quits.
- A gesture that BTT recognizes in the first few millimetres of a swipe, before the switcher opens, can
  still run. Gestures you make *inside* the switcher (swiping back, changing rows) are covered.
- What didn't work, in case you're tempted: a Conditional Activation Group with **Disable BetterTouchTool
  completely**, BTT's **Disable Gesture Recognition** action, and toggling BTT off and on by link (once
  BTT is off it ignores links, including the one to turn it back on).

## Permissions and privacy

SwipeSwitch runs entirely on your Mac. **It contains no network code**: it never connects to the
internet, and it collects, stores and sends nothing about you, your apps or your windows.

| Permission | Required? | What it's used for |
| --- | --- | --- |
| **Accessibility** | Yes | Watching for ⌘Tab (only if you turn on the keyboard option), bringing the app or window you pick to the front (including on other desktops), reading window titles and whether a window is minimized, and noticing which window you last focused so the list is in the right order. |
| **Screen Recording** | Optional | Only to read the *titles* of windows on other desktops before you've visited them. SwipeSwitch never captures, records or saves screen images. |

What else it touches:

- **Trackpad input** is read through macOS's touch framework, which needs no permission. Only finger
  positions are used, and only while a gesture is in progress.
- **Keyboard input:**
  - *While a switcher opened by a swipe is on screen*, SwipeSwitch watches for **Esc** so you can cancel.
    It acts on Esc only, lets every other key through untouched, and stops listening as soon as the
    switcher closes.
  - *If you turn on "Open with ⌘Tab"*, it receives every key press so it can catch ⌘Tab before macOS
    does. It acts only on ⌘Tab and the keys listed above while its switcher is open; every other key
    passes straight through untouched.
  - Nothing typed is stored or sent. With ⌘Tab off and no switcher on screen, it doesn't listen to the
    keyboard at all.
- **Settings** are stored in macOS's normal preferences for the app (`io.github.khameedk.swipeswitch`).
- **Window titles and focus order** are kept in memory while the app runs and are never written to disk.
- **BetterTouchTool links** (only if you turn that option on): SwipeSwitch sends local `btt://` links to
  BTT on your Mac saying whether the switcher is open. Nothing else is sent, and nothing leaves your Mac.

You can check all of this in the source: everything lives in [`Sources/`](Sources) (about 1,700 lines of Swift).

### Security checks

Every change to this repo is checked automatically on GitHub:

| Check | What it does |
| --- | --- |
| **Build** | Builds the app from exactly the code in the repo, then runs [`scripts/check-no-network.sh`](scripts/check-no-network.sh), which fails if the source contains networking code or the built app imports networking functions. |
| **CodeQL** | GitHub's code scanner looks for security problems in the Swift code (also weekly). |
| **OpenSSF Scorecard** | Rates the repo's security practices; the score is the badge at the top. |
| **Release** | Tagged versions are built on GitHub, checked for networking code, and published with a checksum and a signed build-provenance record. |
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
- switching off macOS's own ⌘Tab while the keyboard option is on (restored when you turn it off or quit)

These are looked up at runtime, and the app falls back gracefully if one is missing. A future macOS
update could still change them, so if something stops working after an update, please open an issue.

## Troubleshooting

- **Nothing happens when I swipe.** Check the menu bar icon: "Enabled" should be ticked, and the menu
  shows "No trackpad detected" if SwipeSwitch can't see one. Look for a gesture-conflict warning in
  Settings › Gesture.
- **The switcher opens but doesn't switch apps.** Grant Accessibility access (Settings › Status shows
  whether it's granted). If it's already on, remove SwipeSwitch from the Accessibility list and add it again.
- **It stopped responding after waking from sleep.** SwipeSwitch reconnects to the trackpad after
  waking on its own; if it still doesn't respond, quit it from the menu bar icon and open it again.
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

**README images** are drawn by a script on a mock desktop (no real screenshots); they use macOS's built-in
app icons, which are Apple's trademarks and artwork. To regenerate them:

```bash
swift docs/make_media.swift docs/images
```

Each image's file name includes a fingerprint of its contents, and the script updates the links above, so
a changed image gets a new address and GitHub shows it right away instead of a cached copy.

## License

[MIT](LICENSE)
