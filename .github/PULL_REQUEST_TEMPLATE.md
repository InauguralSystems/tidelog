## What does this PR do?

<!-- Brief description of the change -->

## Checklist

- [ ] Byte-for-byte **round-trip holds** — `decode(encode(x)) == x` and one
      canonical byte sequence per value
- [ ] **Crash-recovery / replay determinism holds** — recovered state exactly
      equals an independent replay of the surviving record prefix
- [ ] `bash test/run.sh` passes locally
- [ ] Any runtime gap or surprising behavior is logged in
      [FINDINGS.md](../FINDINGS.md) (and, if it's an EigenScript bug, filed upstream)
