#!/usr/bin/env bash
# Regression tests for test/replay.sh's verdict (hq#58 TL-REPLAY-1).
#
# replay.sh used to accept any run whose record and replay stdouts were equal:
# exit codes were never read and stderr went to /dev/null, so a tidelog.eigs that
# crashed at line 1, threw mid-digest, or a missing runtime all "replayed
# byte-for-byte". Each plant below is a run that must be rejected, and each is
# matched to the reason replay.sh must give, so removing any one check turns its
# plant green and this test red. The clean control must still pass.
#
# Honors $EIGS like run.sh (default ./eigs); the plants run the real runtime.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
EIGS="${EIGS:-./eigs}"
case "$EIGS" in
  */*) REAL=$(cd "$ROOT" && realpath -e -- "$EIGS" 2>/dev/null) ;;
  *)   REAL=$(command -v -- "$EIGS" 2>/dev/null) ;;
esac
if [ -z "${REAL:-}" ] || [ ! -x "$REAL" ]; then
  echo "FAIL: replay verdict: runtime '$EIGS' not found"; exit 1
fi

TMP=${TMPDIR:-/tmp}/tidelog-replay-verdict-$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fresh () { # make a clean copy of what replay.sh runs
  rm -rf "$TMP/tree"; mkdir -p "$TMP/tree/test"
  cp "$ROOT/test/replay.sh" "$TMP/tree/test/replay.sh"
  cp "$ROOT/tidelog.eigs" "$TMP/tree/tidelog.eigs"
  cp -r "$ROOT/src" "$TMP/tree/src"
}

wrapper () { # name body: a fake runtime that wraps the real one
  printf '#!/usr/bin/env bash\nREAL=%q\n%s\n' "$REAL" "$2" > "$TMP/$1"
  chmod +x "$TMP/$1"
}

fail=0
expect () { # plant runtime reason: replay.sh must exit nonzero naming the reason
  local plant=$1 runtime=$2 reason=$3 out status
  out=$(EIGS="$runtime" bash "$TMP/tree/test/replay.sh" 12345 80 2>&1); status=$?
  if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qF -- "replay: FAILED — $reason"; then
    echo "PASS: replay.sh rejects plant $plant"
  else
    echo "FAIL: replay.sh accepted plant $plant (status=$status, wanted: $reason)"
    printf '%s\n' "$out" | tail -6; fail=1
  fi
}

mkdir -p "$TMP"

# A: crash at line 1 — both runs die identically with empty stdout.
fresh; sed -i '1i this_function_does_not_exist of 1' "$TMP/tree/tidelog.eigs"
expect "A (line-1 crash)" "$REAL" "record run exited nonzero"

# B: throw right after the 'version' line — equal partial stdout.
fresh; sed -i '/^print of ("version "/a throw of "planted mid-digest throw"' "$TMP/tree/tidelog.eigs"
expect "B (mid-digest throw)" "$REAL" "record run exited nonzero"

# C: full digest printed, then a throw — stdout complete, exit code is the only witness.
fresh; printf '%s\n' 'throw of "planted throw after the digest"' >> "$TMP/tree/tidelog.eigs"
expect "C (throw after digest)" "$REAL" "record run exited nonzero"

# D: runtime missing.
fresh
expect "D (missing runtime)" "$TMP/no-such-eigenscript" "record run exited nonzero"

# E: tracing silently off — equal complete digests, but nothing recorded or replayed.
fresh; wrapper notrace 'unset EIGS_TRACE EIGS_REPLAY; exec "$REAL" "$@"'
expect "E (tape not written)" "$TMP/notrace" "tape has no N records"

# F: digest truncated before the 'log' line, exit 0.
fresh; wrapper truncated '"$REAL" "$@" | sed "\$d"; exit "${PIPESTATUS[0]}"'
expect "F (digest truncated)" "$TMP/truncated" "record output does not end with a 'log <hex>' line"

# G: nothing printed, exit 0 — empty == empty.
fresh; wrapper silent 'exit 0'
expect "G (empty output, rc 0)" "$TMP/silent" "record output does not start with a 'version N' line"

# H: replay diverges from the record.
fresh; wrapper diverge '"$REAL" "$@"; rc=$?; [ -n "${EIGS_REPLAY:-}" ] && echo extra; exit "$rc"'
expect "H (replay diverges)" "$TMP/diverge" "record vs replay output differs"

# I: replay run alone fails.
fresh; wrapper replayfail 'if [ -n "${EIGS_REPLAY:-}" ]; then "$REAL" "$@"; exit 3; fi; exec "$REAL" "$@"'
expect "I (replay run exits nonzero)" "$TMP/replayfail" "replay run exited nonzero"

# Control: the unmodified driver on the real runtime must pass.
fresh
out=$(EIGS="$REAL" bash "$TMP/tree/test/replay.sh" 12345 80 2>&1); status=$?
if [ "$status" -eq 0 ] && printf '%s\n' "$out" | grep -qE '^replay: byte-for-byte identical \(seed=12345 ops=80\); tape N-records=[1-9][0-9]* '; then
  echo "PASS: replay.sh accepts clean control"
else
  echo "FAIL: replay.sh rejected clean control (status=$status)"
  printf '%s\n' "$out" | tail -6; fail=1
fi
exit "$fail"
