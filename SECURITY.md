# Security Policy

`tidelog` is a serialization format and a crash-recoverable store written
entirely in pure EigenScript. It opens no network sockets. It does, however,
*deserialize and load store files* — the CBOR decoder and the store's log reader
consume byte streams — so how the codec and the store reader handle malformed or
adversarial input is the one thing worth a report.

## Reporting a vulnerability

Please report security issues privately rather than in a public issue — via
[GitHub private vulnerability reporting](https://github.com/InauguralSystems/tidelog/security/advisories/new)
or by contacting the maintainer at the address on the
[InauguralSystems](https://github.com/InauguralSystems) profile
(`contact@inauguralsystems.com`, subject prefix `[SECURITY]`). Include steps to
reproduce, a minimal malformed input if applicable, and the affected EigenScript
version.

## Scope

- Malformed-input handling of the CBOR decoder (`src/cbor.eigs`) and the store's
  log reader / recovery path (`src/store.eigs`) — the code that consumes
  untrusted bytes.
- Issues in the EigenScript interpreter or runtime itself (a crash on malformed
  input, a bitwise/float edge, a nondeterminism leak) belong in the
  [EigenScript](https://github.com/InauguralSystems/EigenScript) repository,
  which has its own security process.

## Supported versions

The latest tag on `main` is supported. `tidelog` tracks a pinned EigenScript
version (see `.devcontainer/Dockerfile`'s `EIGS_REF`, currently v0.21.2); run
against that or newer.
