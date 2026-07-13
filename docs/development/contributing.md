# Contributing

Keep changes small across the architecture boundaries and pair every behaviour
change with evidence. The repository's canonical policy is
[`CONTRIBUTING.md`](../../CONTRIBUTING.md); this chapter is the working route.

## Local setup and checks

Use a development checkout on `runtimepath` as shown in
[Installation](../getting-started/installation.md). The normal test gate is:

```sh
./scripts/test.sh
```

It checks Lua syntax, runs StyLua when installed, and executes the headless
Neovim suite. For performance-sensitive rendering/history changes, also run:

```sh
./scripts/benchmark.sh
```

Benchmark timing is diagnostic, not a portable pass/fail threshold. Before a
release-oriented change, run `./scripts/release-check.sh`; it additionally
checks JSON Schema, help tags, health, Nix packaging, and whitespace.

## Where changes belong

- Persisted fields start in schema/model and need encode/decode fixtures.
- Model changes are semantic actions, never nested mutations from UI code.
- Geometry stays in pure modules and covers negative coordinates, tangency,
  large origins, and deterministic ties.
- Render features become scene primitives before raster glyphs; add Unicode,
  ASCII, selection, and hit-provenance tests.
- A storage adapter must compare the expected revision immediately before
  mutation and return structured errors. Add conflict/recovery tests, not only
  a successful round trip.
- User workflows use structured forms/action-registry entries so visible keys,
  disabled reasons, footer actions, and palette actions remain consistent.
- Personal furniture data belongs in configuration or project templates;
  built-ins stay generic and use reserved `builtin:` IDs.

Avoid adding dormant flags, compatibility branches, duplicated defaults, or a
second UI path. When replacing an interface, update tests and documentation in
the same change and remove the obsolete implementation after its supported
compatibility decision is explicit.

## Compatibility and documentation

Use Lua 5.1-compatible syntax and Neovim 0.10+ APIs (the primary tested target
is 0.12.4). Runtime dependencies require strong justification; standard
`vim.ui` providers are integration points, not dependencies.

If schema version changes, add one sequential migration, old/new fixtures,
machine-readable schema changes, and recovery guidance. If behaviour or public
configuration changes, update the relevant chapter, Vim help, README landing
page, and changelog. Run a relative-link audit when adding or moving chapters.

Adapted third-party code must retain licensing and be recorded in `NOTICE`.

← [Architecture](architecture.md) | [Documentation home](../README.md) | [Releasing](releasing.md) →
