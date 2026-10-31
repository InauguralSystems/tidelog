#!/usr/bin/env bash
# Regression tests for test/run.sh's child-process verdict handling.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}/tidelog-run-verdict-$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/test"
cp "$ROOT/test/run.sh" "$TMP/test/run.sh"
printf '# fixture\n' > "$TMP/test/replay.sh"
for name in cbor cbor_unsupported store crash_sweep temporal compaction; do
    printf '# fixture\n' > "$TMP/test/test_$name.eigs"
done

cat > "$TMP/fake-eigs" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *test_cbor_unsupported.eigs)
    # run.sh's reject check (#44) expects this one to fail loudly.
    echo 'cbor: cannot encode type fn' >&2; exit 1 ;;
  *test_temporal.eigs)
    case "${PLANTED_FAILURES:-0}" in
      crash) exit 9 ;;
      forged) echo 'temporal: 18 passed, 0 failed'; exit 7 ;;
      0) echo 'temporal: 18 passed, 0 failed' ;;
      *) echo "temporal: 18 passed, ${PLANTED_FAILURES} failed" ;;
    esac
    ;;
  *) echo 'fixture: 1 passed, 0 failed' ;;
esac
EOF
chmod +x "$TMP/fake-eigs"

check_rejected () {
    local plant=$1 out status
    out=$(cd "$TMP" && TIDELOG_SKIP_RUNNER_SELFTEST=1 PLANTED_FAILURES=$plant EIGS="$TMP/fake-eigs" bash test/run.sh 2>&1)
    status=$?
    if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -q '^FAIL: temporal reads (time travel)$' && printf '%s\n' "$out" | grep -q '^SOME FAILED$'; then
        echo "PASS: run.sh rejects temporal plant $plant"
    else
        echo "FAIL: run.sh accepted temporal plant $plant (status=$status)"
        printf '%s\n' "$out" | tail -8
        return 1
    fi
}

fail=0
for plant in 1 10 100 crash forged; do
    check_rejected "$plant" || fail=1
done

out=$(cd "$TMP" && TIDELOG_SKIP_RUNNER_SELFTEST=1 PLANTED_FAILURES=0 EIGS="$TMP/fake-eigs" bash test/run.sh 2>&1)
status=$?
if [ "$status" -eq 0 ] && printf '%s\n' "$out" | grep -q '^PASS: temporal reads (time travel)$' && printf '%s\n' "$out" | grep -q '^ALL PASSED$'; then
    echo 'PASS: run.sh accepts clean control'
else
    echo "FAIL: run.sh rejected clean control (status=$status)"
    fail=1
fi
exit "$fail"
