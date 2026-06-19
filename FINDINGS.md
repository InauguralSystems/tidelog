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

## F-STORE-1 — no binary-append file write — GAP → FIXED upstream (PR #249)

The store appends binary CBOR records to a log, but the only file-write builtin
was `write_text`: truncate-mode (`"w"`) and string-based (`strlen`), so it could
neither append nor write a record containing a NUL byte. `write_bytes of [path,
<list|buffer> {, append}]` (PR #249) writes raw bytes verbatim with an append
flag, pairing with the existing `read_bytes_buf` for recovery. Suite 2050/2050,
ASan-clean. The liferaft→#245 pattern a third time: a real missing primitive,
added to the language.

---

## Store-layer determinism — BY-DESIGN (verified)

The log bytes are a pure function of the operation sequence: CBOR's deterministic
profile fixes each record's encoding, the 4-byte length frame is arithmetic, and
the only I/O on the path (`read_bytes_buf`, `write_bytes`) touches no
nondeterministic builtin. Verified: the same op sequence produces a
byte-identical log across two fresh processes. This is the on-disk analog of
liferaft's in-memory replay determinism, and the foundation for the Phase 3
crash-recovery replay oracle.

The crash model is the simplest sound one: a crash = the process stops, leaving
the file with some byte prefix. Because the log is append-only, the only damage
is a torn *trailing* record; recovery keeps the maximal prefix of complete
length-framed records and discards the torn tail. Verified by a crash-injection
sweep that truncates at EVERY byte offset across several seeded op sequences
(874 checks) and asserts recovery equals an independent in-memory replay of the
surviving record prefix — exact at every possible crash point.

Replay oracle (EIGS_TRACE / EIGS_REPLAY): a recorded run replays byte-for-byte
across seeds. Unlike liferaft (pure seed → zero `N` tape records), tidelog's tape
carries `N` records equal to its file reads — the file is legitimately
nondeterministic *input*, and the tape captures exactly that boundary and nothing
else. The claim is "deterministic given its durable input," proven by the
identical replay.

---

## F-TEMPORAL-1 — native temporal interrogatives don't cover version history — CONSTRAINT

EigenScript's temporal interrogatives (`prev of x`, `what is x at <line>`) record
a *variable's assignment timeline*, keyed by the latest assignment / source line.
That is a different axis from a persistent store's *version history* (records on
disk), and the two don't compose into "value of key K as of version V." So
tidelog implements time travel itself: `store_open_at(path, v)` / `store_get_at`
replay a prefix of the append-only log. The log already carries the full history
for free, and these reads are pure functions of (path, version).

Not a defect — it marks the boundary of the observer/temporal system as a
language-level observation tool rather than a general history API. Recorded so a
future consumer doesn't expect `state_at`-style builtins to span durable
application state.

---

## F-STORE-2 — no atomic file replace / delete — GAP → FIXED upstream (PR #250)

Crash-safe compaction needs an *atomic* swap: write the compacted log to a temp
file, then replace the live log in one indivisible step so a crash can never
leave a half-written log. EigenScript's file I/O was create/read/append-only —
no rename, no delete. Added `rename of [old, new]` (atomic via `rename(2)`) and
`remove_file of path` (PR #250). Suite 2062/2062, ASan-clean. The fourth
primitive this port has driven into the language (after #248 ×2, #249).
