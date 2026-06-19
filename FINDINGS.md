# tidelog — EigenScript findings

Language behaviors surfaced by writing a serialization format and persistent
store in EigenScript. Each is classified:

- **BUG** — a defect; fix upstream in EigenScript.
- **GAP** — a missing primitive the workload genuinely needs.
- **CONSTRAINT** — a real language limit with a clean in-language workaround;
  documented so the next consumer doesn't rediscover it.
- **BY-DESIGN** — behaves as intended; recorded to prevent a false alarm.

---

## F-CBOR-1 — 64-bit byte coding without 64-bit bitwise — CONSTRAINT

CBOR arguments can be 64-bit integers, but EigenScript's bitwise operators are
32-bit. Naively, `n >> 32` for the high bytes of an 8-byte value is unavailable.

**Workaround (clean, exact):** do multi-byte coding in pure arithmetic.
Encoding emits bytes low-to-high with `b = rem % 256; rem = floor(rem / 256)`,
then reverses for big-endian; decoding accumulates `n = n * 256 + byte`. Every
intermediate stays below 2^53, so `%`, `floor`, `*`, and `+` are all exact
integer operations on doubles. No power of 256 is ever materialized (which would
overflow exact range at 256^7 = 2^56), and no bitwise op is used at all.

Verified against RFC 8949 Appendix A, including `1000000000000`
(`1b000000e8d4a51000`, the 8-byte path) and round-trips through `2^53 - 1`.

**Boundary noted:** values in `[2^53, 2^64)` (e.g. CBOR's `2^64 - 1` test
vector) are not exactly representable as doubles and are out of scope for an
integer codec built on EigenScript numbers. If the store layer ever needs full
64-bit keys, that becomes a GAP (a true 64-bit/bignum or byte-buffer integer
type) rather than a constraint — flagged here, not yet needed.

No upstream change required: this is the correct, portable idiom for sub-word
bit math in EigenScript.

---

*(Store-layer findings — NUL/binary buffers, float→bytes, crash-recovery
determinism — to be added as Phases 2–3 land.)*
