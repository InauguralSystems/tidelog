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
#
# Equal stdout alone is not a verdict: two runs that die the same way (a crash at
# line 1, a throw mid-digest, a missing runtime) print equal — possibly empty —
# output. So both runs must exit 0, the record run must print a complete digest
# (first line `version N`, last line `log <hex>`), and the tape must carry at
# least one `N` record. Any failure prints both exit codes and both stderrs.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
EIGS="${EIGS:-./eigs}"
SEED="${1:-12345}"
OPS="${2:-80}"

tape="$(mktemp)"; first="$(mktemp)"; second="$(mktemp)"
err1="$(mktemp)"; err2="$(mktemp)"
recpath="$(mktemp -u)"; reppath="$(mktemp -u)"
trap 'rm -f "$tape" "$first" "$second" "$err1" "$err2" "$recpath" "$reppath"' EXIT

EIGS_TRACE="$tape"  "$EIGS" tidelog.eigs --seed "$SEED" --ops "$OPS" --path "$recpath" 2>"$err1" > "$first"
rc1=$?
EIGS_REPLAY="$tape" "$EIGS" tidelog.eigs --seed "$SEED" --ops "$OPS" --path "$reppath" 2>"$err2" > "$second"
rc2=$?

fail () { # reason
  echo "replay: FAILED — $1 (seed=$SEED ops=$OPS; record rc=$rc1, replay rc=$rc2)"
  if [ -s "$err1" ]; then echo "  record stderr:"; tail -n 8 "$err1" | sed 's/^/    /'; fi
  if [ -s "$err2" ]; then echo "  replay stderr:"; tail -n 8 "$err2" | sed 's/^/    /'; fi
  exit 1
}

[ "$rc1" -eq 0 ] || fail "record run exited nonzero"
[ "$rc2" -eq 0 ] || fail "replay run exited nonzero"
head -n 1 "$first" | grep -qE '^version [0-9]+$' || fail "record output does not start with a 'version N' line"
# Every operation appends a log record, so the digest's hex is non-empty unless
# the workload ran zero operations: then the store is empty and the line is `log `.
if [ "$OPS" = 0 ]; then logre='^log $'; else logre='^log [0-9a-f]+$'; fi
tail -n 1 "$first" | grep -qE "$logre" || fail "record output does not end with a 'log <hex>' line (digest incomplete)"

if ! diff -q "$first" "$second" >/dev/null; then
  echo "replay: FAILED — record vs replay output differs (seed=$SEED ops=$OPS)"
  diff "$first" "$second" | head
  exit 1
fi

nrec="$(grep -c '^N ' "$tape" 2>/dev/null || true)"
[ "${nrec:-0}" -gt 0 ] || fail "tape has no N records (nothing was recorded, so nothing was replayed)"
echo "replay: byte-for-byte identical (seed=$SEED ops=$OPS); tape N-records=${nrec} (= the file reads, the only nondeterministic boundary)"
