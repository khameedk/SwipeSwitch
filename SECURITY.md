# Security Policy

## Reporting a vulnerability

Please report security vulnerabilities privately, not in a public issue, using GitHub's private
vulnerability reporting:

**https://github.com/khameedk/SwipeSwitch/security/advisories/new**

(Or go to the repository's **Security** tab and choose **Report a vulnerability**.) Only the maintainer
and you can see the report.

Please include what you found, how to reproduce it, and the macOS version you tested on.

## What to expect

- **Acknowledgement within 2 weeks** of your report.
- We'll work with you to confirm the issue and agree on a fix and a disclosure date. Fixes are released
  before the vulnerability is disclosed publicly.
- Once fixed, the vulnerability is disclosed in a GitHub security advisory, crediting you unless you'd
  rather stay anonymous.

## Supported versions

Only the latest release and the latest code on the `main` branch are supported. Update to the newest
release, or pull and rebuild (`./build.sh --install`), to get fixes.

## What SwipeSwitch can access

SwipeSwitch asks for **Accessibility** access (required) and, optionally,
**Screen Recording** access. If you turn on the BetterTouchTool option, it also asks to control
**BetterTouchTool** (Automation), which it uses only to set one BTT variable while the switcher is open
and, when you click Add or Remove in its Settings, to add or remove one condition on BTT's swipe gestures.
If you enter a BTT shared secret, SwipeSwitch keeps it in your login Keychain. The app runs with the hardened
runtime, and release builds contain no demo or test code.
See [Permissions and privacy](README.md#permissions-and-privacy) in the README for exactly what each one is used for. It has no network code and
never stores or sends anything about your apps, windows or screen.

## Design notes

### Not sandboxed

SwipeSwitch can't run in macOS's App Sandbox: a sandboxed app can't control other apps through Accessibility
(bringing a window to the front), can't install a keyboard tap that holds back ⌘Tab, and can't make the
window-server calls it uses to find windows on other desktops. What stands in for the sandbox:

- **No network code**, checked on every change in the source and in the built binary
  ([`scripts/check-no-network.sh`](scripts/check-no-network.sh)).
- **One entitlement** (Apple Events, to talk to BetterTouchTool), and the **hardened runtime**, so other
  programs can't load code into SwipeSwitch or attach to it. CI fails if either changes
  ([`scripts/check-hardening.sh`](scripts/check-hardening.sh)).
- **No files** written apart from its own preferences; the BTT shared secret goes in the Keychain.

### Keyboard (⌘Tab, opt-in)

The "Open with ⌘Tab" option is off by default. When it's on, SwipeSwitch installs an **active** keyboard tap
(one that can change or hold back events, not only listen), because it has to stop ⌘Tab reaching macOS and the
app in front. It holds back ⌘Tab itself and, only while that switcher is open (that is, while ⌘ is held after
⌘Tab), every key press: Tab, the arrow keys, Return and Esc move, pick or close the switcher, and other keys are
ignored rather than reaching the app. Modifier keys (⌘, ⇧) always pass through. At all other times every key
passes through unchanged, and nothing typed is stored or logged. A listen-only tap isn't enough: the keys that move the switcher would also reach the app in front
(⌘← would jump to the start of a line, Esc would cancel things). While the option is on it also turns off
macOS's own ⌘Tab switcher, and turns it back on when you turn the option off or quit (only if it was the
one that turned it off).

Without the option, SwipeSwitch only watches for Esc, and holds back only Esc, while a swipe-opened switcher is
on screen.

### Private macOS interfaces

Some of what SwipeSwitch does has no public API, so it calls private system functions. They're looked up at
runtime (`dlopen`/`dlsym`) in Apple's own frameworks, which System Integrity Protection guards and the
hardened runtime only lets Apple-signed code replace, so the risk isn't someone injecting code through them:
it's **Apple changing them** in a macOS update. SwipeSwitch's own copies of their data layouts
([`Sources/Bridge.h`](Sources/Bridge.h), and the token built in `PrivateAPI.windowElementOnAnyDesktop`) would
then be wrong. Where that can be detected, SwipeSwitch turns the feature off (fails closed) and says so in its
menu and in Settings › Status, rather than act on bad data.

| Functions | Used for | If missing or changed |
| --- | --- | --- |
| `MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTUnregisterContactFrameCallback`, `MTDeviceStart`, `MTDeviceStop`, `MTDeviceGetDeviceID`, `MTDeviceGetSensorSurfaceDimensions` (MultitouchSupport) | Reading trackpad touches: the swipe itself | Missing: no swipes (⌘Tab still works). Layout changed: every frame is sanity-checked (finger state, positions between 0 and 1, finger count); after a third of a second of bad frames, swipes turn off with a warning. |
| `MTActuatorCreateFromDeviceID`, `MTActuatorOpen`, `MTActuatorClose`, `MTActuatorActuate` (MultitouchSupport) | The haptic click on each step | No haptics. |
| `_AXUIElementGetWindow` | Matching an Accessibility window to its window ID | Windows mode can't tell windows apart; switching brings the app forward instead. |
| `_AXUIElementCreateWithRemoteToken` | Reaching a window on another desktop | Missing: switching brings the app forward instead. Token format changed: after three lookups in a row find no windows at all, it turns off with a warning. |
| `CGSMainConnectionID`, `CGSCopySpacesForWindows`, `CGSCopyManagedDisplaySpaces`, `CGSCopyWindowsWithOptionsAndTags` | Which desktop a window is on, and telling real windows from closed ones | Falls back to the windows Accessibility reports. |
| `CGSSetSymbolicHotKeyEnabled`, `CGSIsSymbolicHotKeyEnabled` | Turning macOS's own ⌘Tab off while the ⌘Tab option is on | macOS's switcher may show as well. |

Values that come back from Accessibility are type-checked (`CFGetTypeID`) before use, not force-cast.

### Secrets and memory

- The BTT shared secret is read from the Keychain only while the BetterTouchTool option is on, and the copy in
  memory is dropped when you turn it off. It's sent to BTT only as an Apple Event. There's no fallback to BTT's
  `btt://` links, which would put it in a URL that any app can register to receive. If the Keychain won't
  read or save it, Settings says so (it's never kept in the preferences file; one left there by a version
  before 1.3 is deleted at launch).
- Memory isn't wiped after use: Swift strings can't reliably be zeroed (they're copied, including into the
  Apple Event). Instead, the hardened runtime and the lack of a `get-task-allow` entitlement stop other
  programs running as you from reading SwipeSwitch's memory.
- The Keychain item is in your login keychain: stored on this Mac only (not synced), and readable only while
  you're logged in. macOS's stricter "this device only, when unlocked" item settings apply only to the
  data-protection keychain, which needs an Apple-issued developer team ID, so they aren't used.

### What's logged

Only the optional diagnostic log (off by default, turns itself off after an hour) writes anything about
switches, to macOS's log on your Mac. Messages hold counts, positions and timings. App names are logged only
as a hash (`.private(mask: .hash)`), so a session can be followed without the log saying which apps you used.
Window titles, keystrokes and the BTT secret are never logged. A project Semgrep rule
([`.semgrep/logging.yml`](.semgrep/logging.yml)) fails CI if a log message includes anything named like a
title, secret, password, token, key code or app name.

## Checked on the built app

Results for the installed build of 1.6.1 plus the changes above (macOS 27, Apple Silicon), 16 November 2026.
CI repeats the entitlement and hardening checks on every build; the network check below is done by hand.

| Check | Command | Result |
| --- | --- | --- |
| Network sockets | `lsof -nP -a -p $(pgrep -x SwipeSwitch) -i` | None. (Its only socket is a local Unix-domain one, which every macOS app has for talking to the system.) |
| Entitlements | `codesign -d --entitlements - /Applications/SwipeSwitch.app` | Only `com.apple.security.automation.apple-events` |
| Hardened runtime | `codesign -dvv /Applications/SwipeSwitch.app` | `flags=0x10000(runtime)` |
| ASLR | `otool -hv /Applications/SwipeSwitch.app/Contents/MacOS/SwipeSwitch` | `PIE` |
| Stack protection | `nm -u /Applications/SwipeSwitch.app/Contents/MacOS/SwipeSwitch \| grep stack_chk` | `___stack_chk_guard`, `___stack_chk_fail` |
| Swift safety checks | `build.sh` | Built with `-O`, not `-Ounchecked`, so bounds and overflow checks stay on |
| Logs | Every log call in `Sources/` | Counts, indexes, timings, Keychain status codes and hashed app names only |

## Automated checks

Every change is built on GitHub and checked for networking code and hardening, scanned with CodeQL and
Semgrep (including the logging rule above), and rated by OpenSSF Scorecard. Releases are built with a pinned
runner image and Xcode version, only from a tag on a commit that's on `main`. See
[Security checks](README.md#security-checks).
