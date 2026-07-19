# Changelog

All notable changes to `roomplan.nvim` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and plugin releases
use [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Persisted
RoomPlan schema versions are independent from plugin versions.

## [Unreleased]

### Added

- Exact schema-v4 floor plans with deterministic JSON, optional marked Norg
  embedding, preserved extension fields, and explicit sequential migration
  from schema v1, v2, and v3.
- Rectangular and connected L/T/U-shaped room and furniture footprints with
  exact integer/doubled-millimetre geometry, stable part IDs, seam-free walls,
  snapping, containment, validation, and hit provenance.
- A responsive canvas-first workspace with Navigator/Issues, Details, a
  contextual action bar, searchable `?` action palette, compact drawers, and
  buffer-local semantic mappings.
- Structured popup workflows for rooms, furniture, project templates, doors,
  windows, wall/floor outlets, alignment, plan/site settings, measurement, and
  selected-furniture wall placement.
- Direct highlighted compound-footprint editing for rooms, placed furniture,
  and project templates, including topology-safe section add/remove/resize,
  exact snapping, atomic apply/cancel, and explicit item/template update scope.
- Doors, wall-aligned windows with optional sill/head heights, typed multi-slot
  wall and floor outlets, furniture rotation, project catalogues, and external
  dependency-free furniture catalogues.
- Three canvas detail levels, progressive label scaling, view-only rotation,
  compass, terminal-cell aspect calibration, edge-following navigation, and a
  colored field-of-view minimap.
- Offline sunlight studies with persisted plan north/site authority, exact
  date/time controls, three-month seasonal comparison, sunrise-to-sunset
  playback, exposed-wall/window emphasis, clipped floor patches, and daily
  exposure bands.
- Exact two-object measurement, marked-object atomic batch operations, named
  bounded history browsing/restoration, validation issue navigation, and
  selection/MOVE/RESIZE breadcrumbs.
- Conflict-safe standalone and Norg persistence, atomic creation/replacement,
  Save As destination checks, source-revision conflicts, dirty-session quit
  guards, autosave controls, and recovery behavior.
- Public Ex commands and Lua API, strict validated `setup()` options,
  colorscheme-linked highlights with user overrides, configurable glyphs,
  `:checkhealth roomplan`, Vim help, JSON Schemas, and a chaptered handbook.
- Native/lazy.nvim/vim.pack/rocks-git installation guidance, a Nix flake and
  nvf example, Linux/macOS/Windows smoke coverage, and Neovim
  0.10/0.11/0.12/nightly CI.
- Architecture decision records, compatibility/support/security policies,
  issue and pull-request templates, and a guarded release workflow.

### Changed

- Unified contextual commands, labels, availability, disabled reasons, and
  displayed semantic keys in one action registry shared by Details, the
  footer, and the searchable action palette.
- Standardized the main shortcuts around lowercase action/mode keys, uppercase
  object creation or coarse movement, `R` furniture rotation, `S` sunlight,
  `M` minimap, adjacent `,`/`.` zoom, and `gS` Save As.
- Kept analysis, minimap, preview, pane, form, filter, viewport, and playback
  state transient unless it is an authored part of the plan.
- Derived sunlight, minimap, selection, diagnostic, preview, and workspace
  accents from semantic colorscheme groups while preserving explicit
  `RoomPlan*` highlight overrides.
- Split controller, geometry, schema, storage, scene, render, workspace, and
  form responsibilities behind small facades and pure testable boundaries.

### Fixed

- Made the in-popup `/` action search focus-safe and compatible with Neovim
  0.10 through 0.12 without editing read-only result buffers or falling back to
  command-line search.
- Prevented workspace reflow, choice cycling, and companion preview rendering
  from stealing focus from active forms, palettes, UI providers, or unrelated
  windows.
- Snapped movement and resize to crossed nearby walls even when configured
  steps do not divide the remaining millimetres, avoiding overshoot errors.
- Retained and highlighted every simultaneous positive-length wall contact
  during movement and resize, independently from magnetic snap correction.
- Kept zoomed navigation moving by scrolling at the configured Neovim-style
  `canvas.scrolloff` boundary.
- Protected conflicted dirty plans during `:q` by opening the normal resolution
  flow instead of exposing a Lua callback traceback.
- Preserved old-schema and normalized source bytes until an explicit save and
  prevented autosave or reconciliation from silently establishing a migrated
  savepoint.
- Hardened write hooks, symlinks, CRLF/BOM sources, malformed/future documents,
  failed reloads, duplicate source ownership, and post-write divergence.

[Unreleased]: https://github.com/LuixBits/luixbits-roomplanner.nvim/commits/main
