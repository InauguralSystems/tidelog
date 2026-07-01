# Contributing to tidelog

Thanks for your interest. `tidelog` is a serialization format and a
crash-recoverable persistent store written entirely in
[EigenScript](https://github.com/InauguralSystems/EigenScript): the durable
sequel to the liferaft DST, pushing EigenScript's determinism contract onto disk.
See the [README](README.md) for the intent.

## Setup

EigenScript is not vendored here. Either build it alongside this repo (the `eigs`
symlink points at a sibling `EigenScript/src/eigenscript` build), or open the repo
in a devcontainer / [Codespace](https://codespaces.new/InauguralSystems/tidelog)
(which builds the pinned EigenScript for you).

```sh
# local: build EigenScript from source, then
./test/run.sh                        # full suite (honors $EIGS, default ./eigs)
eigenscript test/test_cbor.eigs      # run a single test program
```

CI runs `test/run.sh` in the pinned devcontainer on every push and PR.

## The discipline (what makes a good contribution here)

- **Durable determinism is the point.** The contract is byte-for-byte: one
  canonical byte sequence per value, `decode(encode(x)) == x`, and crash-recovery
  that reconstructs *exactly* the state an independent replay of the surviving
  record prefix would. If a change can't hold that, it doesn't belong here.
- **Crash-safety at every offset.** A torn trailing record must be discarded and
  the clean prefix must survive; the compaction swap must leave either the old or
  new log whole after a crash at any point. New store operations must extend, not
  weaken, that guarantee.
- **Surface gaps, don't work around them.** When the runtime does something wrong
  or surprising (a missing primitive, a nondeterminism leak, a bitwise/float
  edge), log it in [FINDINGS.md](FINDINGS.md) and file it upstream in
  [EigenScript](https://github.com/InauguralSystems/EigenScript) — surfacing those
  gaps is half the point of this repo.

## Before you open a PR

- `bash test/run.sh` passes locally (codec round-trip, store ops + recovery, the
  every-offset crash sweep, temporal reads, compaction, and the replay /
  cross-process determinism oracles).
- Keep the prevailing style: `snake_case`, sectioned files with header comments.
- Every changed/added `.eigs` parses and runs.

## Reporting bugs

Open an issue with the program and how you ran it. For security concerns see
[SECURITY.md](SECURITY.md).
