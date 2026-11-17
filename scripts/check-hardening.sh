#!/bin/bash
# Checks that a built SwipeSwitch.app keeps its hardening, so a change that weakens it fails CI. You can run it too:
#   ./scripts/check-hardening.sh [path/to/SwipeSwitch.app]   (default: build/SwipeSwitch.app)
set -euo pipefail
cd "$(dirname "$0")/.."
app=${1:-build/SwipeSwitch.app}
bin="$app/Contents/MacOS/SwipeSwitch"
status=0
ok() { echo "OK: $1"; }
fail() { echo "FAIL: $1"; status=1; }

# 1. Entitlements: exactly one, Apple Events (to BetterTouchTool). Anything added (e.g. get-task-allow, which lets
#    other programs attach to the app, or disable-library-validation) fails.
want='{"com.apple.security.automation.apple-events":true}'
got=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo "none")
if [ "$got" = "$want" ]; then ok "entitlements are exactly $want"; else fail "entitlements are $got, expected $want"; fi

# 2. Hardened runtime (other programs can't inject code into the app).
# (Outputs are captured first: with pipefail, `grep -q` stopping early would make the pipeline look failed.)
sig=$(codesign -dvv "$app" 2>&1 || true)
if grep -qE '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<<"$sig"; then ok "hardened runtime is on"
else fail "hardened runtime is off"; fi

# 3. Position-independent executable (address space layout randomization).
if grep -qw PIE <<<"$(otool -hv "$bin")"; then ok "binary is PIE (ASLR)"; else fail "binary is not PIE"; fi

# 4. Stack protection (the compiler's stack canary is used).
if grep -q '___stack_chk_guard' <<<"$(nm -u "$bin")"; then ok "stack protection is in use"
else fail "no stack protection symbols in the binary"; fi

# 5. Swift's runtime safety checks (array bounds, integer overflow, exclusive access) stay on.
if grep -nE -- '-Ounchecked|-enforce-exclusivity=unchecked|-disable-.*-check' build.sh; then
  fail "build.sh turns off Swift's safety checks (see above)"
else ok "Swift safety checks are on (-O, not -Ounchecked)"; fi

exit $status
