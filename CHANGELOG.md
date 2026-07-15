# Changelog

All notable changes to `roomplan.nvim` will be documented here.

## [Unreleased]

- Initial strict schema-v1 model, JSON codec, metric parser, semantic actions,
  bounded history, geometry, snapping, door swing calculations, and validation.
- Interactive Unicode/ASCII canvas with hit testing, viewport controls,
  Navigator, Issues, Details, configurable buffer-local mappings, and menus.
- Canvas-first responsive workspace with a default-visible 26-column
  Navigator, default-hidden 30-column Details pane, focus-or-toggle mappings
  and commands, manual-close persistence, one-line canvas header/contextual
  footer, and bordered drawers for narrow terminals.
- Semantic colors and active-pane chrome, compact object/details presentation,
  bordered collapsible Details sections, and an explicit `[?] More` overflow
  count backed by a complete grouped action palette with disabled reasons.
- Optional palette-based room and furniture colors, selected through standard
  `vim.ui`, persisted compatibly in schema v1, and rendered without masking
  selection or diagnostics.
- Structured Room, Furniture, Door, Alignment, Plan, Custom Template, and
  geometry-edit forms with conditional fields, normalized measurements,
  inline validation, textual previews, stale-revision guards, atomic
  Apply/Cancel, and an explicit invalid-draft policy where supported.
- Native `j/k`/Enter action palette for `:RoomPlan`, session choice, and the
  non-empty Add menu; custom templates are visible in Objects.
- Centralized semantic/default-lhs mapping overrides across workspace panes,
  Canvas, forms, palettes, contextual actions, and displayed action/form hints.
- Runtime `:RoomPlanAspect [ratio]` calibration for terminal/font cell geometry;
  the canvas refits without changing model data, history, or unrelated options.
- Transient 90-degree canvas rotation with screen-relative movement and pan,
  north compass, buffer-local controls, command, and Lua API; saved geometry is
  never rotated.
- Dependency-free furniture defaults from validated inline Lua definitions or
  versioned JSON files, with atomic setup, project-local precedence, defensive
  copies, bounded input, and an option to replace the visible built-in
  catalogue without breaking existing built-in references.
- Conflict-safe standalone and Norg persistence, atomic new-file creation,
  Save As destination checks, staged-write recovery, and native quit guards.
- Revision-bound destructive confirmations, retained-model protection after
  failed reloads, symlink-safe Save As checks, and UTF-8 BOM/CRLF round trips.
- Health checks, JSON Schema, fixtures, help, documentation, and a Neovim
  0.10/0.11/0.12.4/nightly plus cross-platform CI matrix.
- First-class Nix flake package, overlay, nvf example, actionlint/build smoke,
  manager-neutral installation guidance, and documented lazy.nvim,
  rocks-git.nvim, vim.pack, and `vim.ui` provider compatibility.
- Release fixture matrix for malformed, future-version, layout-invalid,
  extension-preserving, and legacy embedded documents.
- Removed the superseded classic UI modules, dormant PICK/preview state, and
  inert wall-thickness setting while keeping old document fields losslessly
  readable as extensions.
- Split controller and workspace orchestration behind stable thin facades, and
  replaced historical implementation plans with a linked documentation
  handbook and compact offline help.
