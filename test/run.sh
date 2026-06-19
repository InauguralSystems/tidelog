#!/usr/bin/env bash
# tidelog test suite. Honors $EIGS (default ./eigs). Run from anywhere.
set -uo pipefail
cd "$(dirname "$0")/.."
EIGS="${EIGS:-./eigs}"
fail=0

unit () { # name file marker
  local out; out="$("$EIGS" "$2" 2>/dev/null)"
  if printf '%s\n' "$out" | grep -q -- "$3"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"; printf '%s\n' "$out" | tail -8; fail=1
  fi
}

echo "--- format (CBOR / RFC 8949) ---"
unit "cbor codec" test/test_cbor.eigs "0 failed"

echo "---"
if [ "$fail" -eq 0 ]; then echo "ALL PASSED"; else echo "SOME FAILED"; fi
exit "$fail"
