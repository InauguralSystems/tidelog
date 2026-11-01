#!/usr/bin/env bash
# Regression tests for test/replay.sh's verdict (#49; hq#58 TL-REPLAY-1).
#
# replay.sh used to accept any run whose record and replay stdouts were equal:
# exit codes were never read and stderr went to /dev/null, so a tidelog.eigs that
# crashed at line 1, threw mid-digest, or a missing runtime all "replayed
# byte-for-byte". Each plant below is a run that must be rejected, and each is
# matched to the reason replay.sh must give, so removing any one check turns its
# plant green and this test red. The clean control must still pass.
#
# The last block plants run.sh itself: a replay.sh that fails must make run.sh
# fail, and TIDELOG_SKIP_RUNNER_SELFTEST=1 set on a real tree must fail too.
#
# Honors $EIGS like run.sh (default ./eigs); the plants run the real runtime.
# Portable shell only (no GNU sed -i / realpath), so it runs on stock macOS.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
EIGS="${EIGS:-./eigs}"
case "$EIGS" in
  */*) REAL=$(cd "$ROOT" && cd "$(dirname -- "$EIGS")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename -- "$EIGS")") ;;
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

edit () { # file cmd...: rewrite file through a filter, in place
  local f=$1; shift
  "$@" < "$f" > "$f.new" && mv "$f.new" "$f"
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
fresh; edit "$TMP/tree/tidelog.eigs" awk 'NR == 1 { print "this_function_does_not_exist of 1" } { print }'
expect "A (line-1 crash)" "$REAL" "record run exited nonzero"

# B: throw right after the 'version' line — equal partial stdout.
fresh; edit "$TMP/tree/tidelog.eigs" awk '{ print } /^print of \("version "/ { print "throw of \"planted mid-digest throw\"" }'
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

# run.sh must act on replay.sh's verdict. A fixture tree holds run.sh, a stub
# replay.sh, and a fake runtime that passes every unit row.
runtree () { # replay_rc: build the fixture tree; its replay.sh exits replay_rc
  rm -rf "$TMP/run"; mkdir -p "$TMP/run/test"
  cp "$ROOT/test/run.sh" "$TMP/run/test/run.sh"
  for name in cbor cbor_unsupported store crash_sweep temporal compaction; do
    printf '# fixture\n' > "$TMP/run/test/test_$name.eigs"
  done
  printf '#!/usr/bin/env bash\nif [ %s -ne 0 ]; then echo "replay: FAILED — planted (seed=$1)"; exit %s; fi\necho "replay: byte-for-byte identical (seed=$1)"\n' \
    "$1" "$1" > "$TMP/run/test/replay.sh"
  cat > "$TMP/run/fake-eigs" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  *test_cbor_unsupported.eigs) echo 'cbor: cannot encode type fn' >&2; exit 1 ;;
  *) echo 'fixture: 1 passed, 0 failed' ;;
esac
FAKE
  chmod +x "$TMP/run/fake-eigs"
}
runsh () { # run the fixture's run.sh with the self-test recursion guard set
  (cd "$TMP/run" && TIDELOG_SKIP_RUNNER_SELFTEST=1 EIGS="$TMP/run/fake-eigs" bash test/run.sh 2>&1)
}

# J: replay.sh exits 1 -> run.sh names the seed, shows the reason, fails.
runtree 1; out=$(runsh); status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'FAIL: replay seed=1' \
   && printf '%s\n' "$out" | grep -qxF 'replay: FAILED — planted (seed=1)' \
   && ! printf '%s\n' "$out" | grep -q '^PASS: replay byte-for-byte' \
   && printf '%s\n' "$out" | grep -qx 'SOME FAILED'; then
  echo "PASS: run.sh rejects plant J (replay.sh exits 1)"
else
  echo "FAIL: run.sh accepted plant J (replay.sh exits 1; status=$status)"
  printf '%s\n' "$out" | tail -8; fail=1
fi

# K: the self-test skip set on a real tree (one holding tidelog.eigs) -> run.sh fails.
runtree 0; printf '# fixture\n' > "$TMP/run/tidelog.eigs"; out=$(runsh); status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -q '^FAIL: TIDELOG_SKIP_RUNNER_SELFTEST=1 outside a self-test fixture' \
   && printf '%s\n' "$out" | grep -qx 'SOME FAILED'; then
  echo "PASS: run.sh rejects plant K (self-test skip on a real tree)"
else
  echo "FAIL: run.sh accepted plant K (self-test skip on a real tree; status=$status)"
  printf '%s\n' "$out" | tail -8; fail=1
fi

# Control: replay.sh exits 0 in a fixture tree -> run.sh passes.
runtree 0; out=$(runsh); status=$?
if [ "$status" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'PASS: replay byte-for-byte (5 seeds x 80 ops)' \
   && printf '%s\n' "$out" | grep -qx 'ALL PASSED'; then
  echo "PASS: run.sh accepts clean replay control"
else
  echo "FAIL: run.sh rejected clean replay control (status=$status)"
  printf '%s\n' "$out" | tail -8; fail=1
fi
exit "$fail"
