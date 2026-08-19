# Changelog

All notable changes to `roomplan.nvim` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and plugin releases
use [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Persisted
RoomPlan schema versions are independent from plugin versions.

## [Unreleased]

## [0.1.0] - 2026-08-19

First public release.

### Added

- Exact millimetre floor plans with deterministic JSON, optional marked Norg
  storage, and explicit migration from document schemas v1 through v4.
- Rectangular, L-shaped, and connected multi-section rooms and furniture with
  direct footprint editing and validation.
- Single-leaf doors, windows with optional height and room connections, and
  typed wall or floor outlets.
- A responsive keyboard-first workspace with Navigator, Issues, Details,
  searchable contextual actions, canvas zoom and rotation, and a minimap.
- Exact room alignment, clearance measurement, furniture wall placement,
  marked batch operations, and bounded named undo history.
- Built-in, Lua, JSON, and project-local furniture catalogues.
- An approximate offline clear-sky 2D sunlight study with date and time
  controls, playback, and daily exposure bands.
- Multiple live plans, conflict-aware atomic saving, guarded Save As, and
  optional conservative autosave for standalone JSON and Norg sources.
- Public Ex commands and Lua API, validated configuration, semantic keymaps
  and highlights, `:checkhealth roomplan`, Vim help, and a linked handbook.
- Installation paths for lazy.nvim, `vim.pack`, native packages, Nix and nvf,
  and rocks-git.nvim, with CI across Neovim 0.10, 0.11, 0.12, and nightly.

### Changed

- Unified action names, keys, availability, and disabled reasons across the
  action bar, Details, and searchable action window.
- Kept viewport, pane, preview, minimap, form, filter, and study state
  transient unless it is authored plan data.
- Derived workspace, selection, diagnostic, minimap, and sunlight colours from
  the active colour scheme while preserving explicit `RoomPlan*` overrides.

### Fixed

- Kept forms and action search focused across workspace redraws and supported
  `vim.ui` providers.
- Snapped movement and resizing to crossed nearby walls when the configured
  step did not divide the remaining distance.
- Preserved every simultaneous positive-length wall contact during movement
  and resizing.
- Protected dirty or migrated sources from silent writes during conflicts,
  reloads, autosave, and quit handling.
- Hardened symlink, CRLF/BOM, malformed document, failed reload, and duplicate
  source handling.

[Unreleased]: https://github.com/LuixBits/luixbits-roomplanner.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/LuixBits/luixbits-roomplanner.nvim/releases/tag/v0.1.0
