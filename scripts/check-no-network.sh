#!/bin/bash
# Checks that SwipeSwitch contains no networking code. CI runs this on every change; you can run it too.
#   ./scripts/check-no-network.sh            checks the source
#   ./scripts/check-no-network.sh <binary>   also checks a built binary's imported symbols
set -euo pipefail
cd "$(dirname "$0")/.."

status=0

# 1. Source: networking APIs (Foundation, Network, CFNetwork, BSD sockets, WebKit).
pattern='URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|import Network|CFNetwork|CFSocket|CFStream|getaddrinfo|[^a-zA-Z_]socket\(|[^a-zA-Z_]connect\(|WKWebView|import WebKit'
if grep -nE "$pattern" Sources/*; then
  echo "FAIL: networking code found in Sources/ (see above)."
  status=1
else
  echo "OK: no networking code in Sources/."
fi

# 2. Binary: symbols the app itself imports (system frameworks it links are not counted).
if [ $# -ge 1 ]; then
  bad=$(nm -u "$1" | grep -E '_socket$|_connect$|_getaddrinfo$|URLSession|NWConnection|NWListener|CFSocket|CFStream' || true)
  if [ -n "$bad" ]; then
    echo "FAIL: the binary imports networking symbols:"
    echo "$bad"
    status=1
  else
    echo "OK: the binary imports no networking symbols."
  fi
fi

exit $status
