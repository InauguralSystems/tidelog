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

echo "--- store (log-structured KV + crash recovery) ---"
unit "store ops + recovery" test/test_store.eigs "0 failed"

echo "--- determinism (store log, two fresh processes byte-identical) ---"
det_drv='load_file of "src/cbor.eigs"
load_file of "src/store.eigs"
write_bytes of ["/tmp/tidelog_det.log", [], 0]
s is store_open of "/tmp/tidelog_det.log"
store_put of [s, "a", 1]
store_put of [s, "b", {"x":[1,2,3],"f":2.5}]
store_delete of [s, "a"]
store_put of [s, "c", "hello"]
buf is read_bytes_buf of "/tmp/tidelog_det.log"
out is ""
hexd is ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"]
for i in range of (buf_len of buf):
    bb is buf_get of [buf, i]
    out is out + hexd[floor of (bb/16)] + hexd[bb % 16]
print of out'
printf '%s\n' "$det_drv" > /tmp/tidelog_det_drv.eigs
da=$("$EIGS" /tmp/tidelog_det_drv.eigs 2>/dev/null)
db=$("$EIGS" /tmp/tidelog_det_drv.eigs 2>/dev/null)
if [ -n "$da" ] && [ "$da" = "$db" ]; then echo "PASS: log byte-identical across processes"; else echo "FAIL: store log diverged"; fail=1; fi
rm -f /tmp/tidelog_det.log /tmp/tidelog_det_drv.eigs

echo "---"
if [ "$fail" -eq 0 ]; then echo "ALL PASSED"; else echo "SOME FAILED"; fi
exit "$fail"
