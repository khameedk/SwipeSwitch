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
See [Permissions and privacy](README.md#permissions-and-privacy) in the README for exactly what each one is used for. It has no network code and
never stores or sends anything about your apps, windows or screen. While a swipe-opened switcher is on
screen it watches for Esc (to cancel) and nothing else. If you turn on the optional ⌘Tab keyboard trigger,
it also receives key presses so it can catch ⌘Tab; it acts only on ⌘Tab and the keys that move its
switcher, and lets everything else through untouched.

## Automated checks

Every change is built on GitHub and checked for networking code
(`scripts/check-no-network.sh`), scanned with CodeQL, and rated by OpenSSF Scorecard.
See [Security checks](README.md#security-checks).
