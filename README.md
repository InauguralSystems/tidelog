# tidelog

A serialization format and a crash-recoverable persistent store, **written
entirely in EigenScript** — a deliberate stress test of the language on the one
axis its prior consumer projects never touched: turning live values into durable
bytes and back, byte-for-byte, across process death.

tidelog is the durable sequel to the liferaft DST. liferaft proved EigenScript
could run a deterministic *in-memory* state machine reproducibly from a seed;
tidelog pushes the same determinism contract onto *disk*: the same writes, after
a crash and recovery, must reconstruct the same state.

## Why this exercises EigenScript specifically

Persistence lands on EigenScript's sharpest edges:

- **Sub-word bit math.** EigenScript's bitwise operators are 32-bit, but binary
  formats encode 64-bit lengths and integers. tidelog does multi-byte coding in
  pure division/modulo arithmetic (exact for values < 2^53). See
  `FINDINGS.md` F-CBOR-1.
- **NUL and binary data.** Strings are C-terminated, so any byte stream
  containing `0x00` must travel through buffers, not strings — exactly where the
  store layer will live.
- **Float → raw bytes.** Serializing an IEEE-754 double to its 8 bytes in a
  language whose numbers are finite doubles is an open question this project
  intends to answer (or to turn into an upstream primitive request).

Every divergence, every nondeterminism leak, every missing primitive is a
candidate EigenScript finding — fixed upstream where it's a real gap, documented
where it's a deliberate constraint. `FINDINGS.md` is a primary deliverable.

## Plan (staged, smallest viable slice first)

1. **Format — CBOR (RFC 8949), deterministic-encoding profile.** One canonical
   byte sequence per value. Oracles: the RFC's Appendix A test vectors
   (external/authoritative) and `decode(encode(x)) == x` (round-trip).
   - [x] unsigned + negative integers (major 0/1), >32-bit arithmetic path
   - [x] byte strings (buffers, NUL-safe) + text strings (str)
   - [x] arrays, maps (deterministic key order), float64, null
   - [x] RFC 8949 Appendix A vectors + round-trip + canonical fixed-point
2. **Store — append-only log-structured KV (Bitcask-style).** ✅ DONE.
   `src/store.eigs`: each put/delete appends a length-framed CBOR record; an
   in-memory keydir holds the latest value per key; `store_open` replays the log
   to recover. Crash model: a torn trailing record is discarded, the clean
   prefix survives. 21 checks (ops, recovery-equivalence, three crash-truncation
   points, binary/nested values) + cross-process log determinism.
3. **Durable determinism.** Crash injection mid-write + a recovery-equivalence
   oracle (recovered state == committed prefix), wired through
   `EIGS_TRACE`/`EIGS_REPLAY`, with the temporal interrogatives querying the
   store's past state.

## Layout

    src/cbor.eigs        CBOR codec
    test/test_cbor.eigs  RFC vectors + round-trip
    test/run.sh          full suite (honors $EIGS, default ./eigs)
    eigs                 symlink to the EigenScript binary
    FINDINGS.md          language findings surfaced by the port

## Running

    ./test/run.sh

Private until EigenScript clears the GitHub Linguist threshold.
