---
name: Bug Report
about: Report a bug in tidelog (the codec, the store, crash recovery/replay, or the tests)
title: ""
labels: bug
assignees: ""
---

**Describe the bug**
What went wrong — e.g. a codec round-trip mismatch (`decode(encode(x)) != x`), a
crash-recovery or replay divergence (recovered state differs from an independent
replay of the surviving prefix), or a store operation (`store_put` / `store_get` /
`store_delete` / `store_compact` / a temporal read) failing or returning the wrong
value.

**To reproduce**
Which program and how you ran it:
```sh
./test/run.sh                        # full suite
eigenscript test/test_cbor.eigs      # or test_store / test_crash_sweep / test_temporal / test_compaction
bash test/replay.sh 42 80            # replay a seeded op sequence byte-for-byte
```

**Expected vs actual**
What you expected (which byte sequence / recovered value) vs what happened
(include output; hex dumps help for codec/store issues).

**Environment**
- OS: [e.g., Ubuntu 24.04]
- EigenScript version: [output of `eigenscript --version`]
- tidelog version/tag: [e.g. v0.1.0]

> If the root cause is the EigenScript language or runtime itself (a missing
> primitive, a nondeterminism leak, a bitwise/float edge), it belongs in the
> [EigenScript repo](https://github.com/InauguralSystems/EigenScript/issues) —
> and it's likely worth a note in [FINDINGS.md](../../FINDINGS.md).
