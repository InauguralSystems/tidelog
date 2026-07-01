---
name: Feature Request
about: Suggest a new format capability or store operation
title: ""
labels: enhancement
assignees: ""
---

**What capability would this add?**
tidelog is a serialization format plus a crash-recoverable store, held to a
durable-determinism contract: byte-for-byte round-trips and crash-recovery that
exactly equals an independent replay. Describe the new format capability (a CBOR
major type / encoding profile) or store operation (a new read/write/maintenance
primitive) and what it would let a consumer do.

**How would it stay deterministic and crash-safe?**
One canonical byte sequence per value; any log mutation must leave a recoverable
state after a crash at any offset. Sketch how the proposal preserves that.

**Alternatives considered**
Any existing capability (the CBOR codec, the log-structured store, temporal
reads, compaction) that already covers part of this.
