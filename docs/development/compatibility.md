# Compatibility policy

RoomPlan versions the plugin, persisted plans, and external furniture
catalogues independently. This page defines which surfaces are stable and how
changes are introduced.

## Supported Neovim versions

The current release line supports Neovim 0.10 and newer. CI exercises the
latest selected patch of 0.10 and 0.11, the primary 0.12 patch, and a
non-blocking nightly build. The exact required jobs are the versions listed in
the repository workflow and release checklist.

A supported Neovim line is not removed in a patch release. Removing one
requires a plugin minor release, a changelog entry, installation-documentation
updates, and a prior roadmap or deprecation notice when practical.

## Plugin SemVer

RoomPlan uses Semantic Versioning for tagged plugin releases:

- patches contain compatible fixes and documentation improvements;
- before `1.0.0`, minor releases may change documented interfaces, but every
  breaking change must be intentional, called out prominently, and include a
  migration path where one is possible;
- after `1.0.0`, documented incompatible changes require a major release.

The `main` branch is tested development source. Tagged releases are the stable
installation targets. Security and correctness fixes target the newest release
line unless the security policy announces additional supported lines.

## Public and internal surfaces

The compatibility contract includes:

- documented functions returned by `require("roomplan")`;
- documented `:RoomPlan...` commands and their argument behavior;
- accepted `setup()` options and semantic mapping names;
- documented highlight groups;
- the current RoomPlan document schema and supported migrations;
- the documented external furniture-catalogue format.

Other `lua/roomplan/*` modules are implementation details unless a reference
chapter explicitly declares them public. The low-level
`require("roomplan.api").dispatch()` integration follows semantic model
actions, but individual action payloads may grow before `1.0.0`; integrations
should pin a plugin release and test the actions they use.

Public names should normally be deprecated for at least one minor release
before removal. Immediate removal is reserved for unsafe behavior, accidental
undocumented exposure, or a change required to prevent data loss.

## Document-schema compatibility

Plugin SemVer never implies a document schema version. RoomPlan currently
writes schema v4 and reads schemas v1 through v4 using tested, sequential
migrations. Loading or normalizing an old source does not rewrite it; an
explicit save is required. Future schemas are rejected rather than guessed,
and downgrades are not supported.

Changing the schema requires a new integer version, one forward migration,
old/new fixtures, JSON Schema updates, validation, documentation, and recovery
behavior. See [ADR-0003](../adr/0003-independent-plugin-and-schema-versioning.md).

## Deprecation and release notes

Deprecations and breaking changes belong in `CHANGELOG.md`, the affected
reference chapter, Vim help, and release notes. A deprecation states the old
surface, replacement, earliest removal version, and whether saved plans are
affected.

← [Architecture](architecture.md) | [Documentation home](../README.md) | [ADRs](../adr/README.md) →
