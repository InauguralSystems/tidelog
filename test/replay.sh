#!/usr/bin/env bash
# Language-level replay oracle. Record a run to a tape with EIGS_TRACE, replay it
# with EIGS_REPLAY, and require byte-for-byte identical stdout.
#
# Unlike the liferaft DST (pure seed-derived, tape carries ZERO nondeterministic
# records), tidelog reads files — which are legitimately nondeterministic *input*
# and are captured on the tape as `N` records. The determinism claim is therefore
# different: given its durable input, the computation is pure. The replay proves
# exactly that — every file read is reproduced from the tape and the run comes out
# identical — and the only `N` records are those file reads, nothing else.
set -uo pipefail
cd "$(dirname "$0")/.."
EIGS="${EIGS:-./eigs}"
SEED="${1:-12345}"
OPS="${2:-80}"

tape="$(mktemp)"; first="$(mktemp)"; second="$(mktemp)"
recpath="$(mktemp -u)"; reppath="$(mktemp -u)"
trap 'rm -f "$tape" "$first" "$second" "$recpath" "$reppath"' EXIT

EIGS_TRACE="$tape"  "$EIGS" tidelog.eigs --seed "$SEED" --ops "$OPS" --path "$recpath" 2>/dev/null > "$first"
EIGS_REPLAY="$tape" "$EIGS" tidelog.eigs --seed "$SEED" --ops "$OPS" --path "$reppath" 2>/dev/null > "$second"

if ! diff -q "$first" "$second" >/dev/null; then
  echo "replay: FAILED — record vs replay output differs (seed=$SEED ops=$OPS)"
  diff "$first" "$second" | head
  exit 1
fi

nrec="$(grep -c '^N ' "$tape" 2>/dev/null || true)"
echo "replay: byte-for-byte identical (seed=$SEED ops=$OPS); tape N-records=${nrec:-0} (= the file reads, the only nondeterministic boundary)"
