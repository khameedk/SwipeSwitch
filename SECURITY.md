# Security Policy

## Reporting a vulnerability

Please report security issues privately rather than in a public issue:
use **Security › Report a vulnerability** on this repository's GitHub page.

Include what you found, how to reproduce it, and the macOS version you tested on.
You should get a reply within a week.

## Supported versions

Only the latest code on the `main` branch is supported. Pull and rebuild
(`./build.sh --install`) to get fixes.

## What SwipeSwitch can access

SwipeSwitch asks for **Accessibility** access (required) and, optionally,
**Screen Recording** access. See [Permissions and privacy](README.md#permissions-and-privacy)
in the README for exactly what each one is used for. It has no network code and
never stores or sends anything about your apps, windows or screen. If you turn on the optional ⌘Tab
keyboard trigger, it also receives key presses so it can catch ⌘Tab; it acts only on ⌘Tab and the keys
that move its switcher, and lets everything else through untouched.

## Automated checks

Every change is built on GitHub and checked for networking code
(`scripts/check-no-network.sh`), scanned with CodeQL, and rated by OpenSSF Scorecard.
See [Security checks](README.md#security-checks).
