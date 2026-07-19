## Problem and outcome

<!-- Explain the user or maintenance problem and the resulting behavior. -->

## Evidence

<!-- List tests, screenshots, reproduction, benchmarks, or manual checks. -->

- [ ] `./scripts/test.sh`
- [ ] Relevant focused tests
- [ ] `./scripts/release-check.sh` for release-sensitive changes

## Compatibility and safety

- [ ] I updated tests and user documentation for behavior or public-surface changes.
- [ ] I updated `CHANGELOG.md` for user-visible changes.
- [ ] Persisted changes use semantic actions and include validation.
- [ ] Schema changes include one sequential migration, fixtures, JSON Schema, and recovery documentation.
- [ ] Persistence/lifecycle changes include conflict or recovery coverage.
- [ ] New third-party material is compatible with GPL-3.0-only and recorded in `NOTICE`.
- [ ] I considered Unicode/ASCII, compact layouts, focus ownership, and configurable semantic mappings where relevant.

## Decision record

<!-- Link an ADR when this introduces or supersedes a durable cross-cutting decision. Otherwise write "Not needed". -->
