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

## F-CBOR-2 — bytes→value primitives missing — GAP → FIXED upstream (PR #248)

Two CBOR types needed primitives no builtin provided. Both became upstream
EigenScript builtins (PR #248, suite 2040/2040, ASan-clean):

1. **Text-string decode (`str_from_bytes`).** `ord of s[i]` returns a raw byte
   (lossless *encode*), but `chr` could not invert it for bytes ≥128 — `chr`
   treats its argument as a Unicode *codepoint* and emits UTF-8, not the byte.
   So a non-ASCII text string encoded faithfully but could not be decoded back
   into a native string. `str_from_bytes of <list|buffer>` writes bytes verbatim.
   (Strings are C-terminated, so a NUL byte ends the string — NUL-bearing binary
   stays in a buffer, which is exactly CBOR's byte-string/text-string split.)

2. **Float64 codec (`f64_to_bytes` / `f64_from_bytes`).** CBOR major-type 7
   needs the 8 raw IEEE-754 bytes of a double; 32-bit bitwise cannot reach them
   and there was no float→bytes path. The builtins emit/read big-endian IEEE-754
   (portable across host endianness). Verified against RFC 8949 Appendix A
   (`1.1` → `3ff199999999999a`, `-4.1` → `c010666666666666`).

This is the liferaft pattern repeating: the consumer project surfaces a real
missing primitive, which is added to the language rather than worked around.

---

## F-CBOR-3 — no native boolean type — CONSTRAINT

`type of (1 == 1)` is `"num"`; EigenScript has no distinct boolean. The codec
therefore never emits CBOR simple `true`/`false` (booleans flow through the
integer path as 1/0); on decode, simple `true`/`false` map to 1/0. Documented so
a future schema layer doesn't expect a round-trippable bool type. No action.

Related guard: a number is encoded as a CBOR integer only when it is a whole
number within ±(2^53−1). Larger integer-valued numbers (e.g. `1e300`, where
`floor(v) == v` is still true) exceed exact-integer range and are encoded as
float64 — routing them to the integer path silently corrupted the low bytes
(caught by the `1e300` round-trip test).

---

*(Store-layer findings — append-only log, crash-recovery determinism — to be
added as Phases 2–3 land.)*
