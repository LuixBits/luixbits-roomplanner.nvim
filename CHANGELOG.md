# Changelog

All notable changes to `roomplan.nvim` will be documented here.

## [Unreleased]

- Moved full-action search into the `?` popup. `/` now starts a visible search
  row, every typed character immediately reduces the grouped results, and
  `Enter` runs the first match while `Esc` returns to action navigation. It no
  longer uses `vim.ui.input` or a command-line prompt, and compact one-key
  palettes remain unchanged. Search now uses a dedicated native prompt buffer
  over a fixed-size, read-only results window. Result redraws cannot move its
  cursor or steal focus, prompt buffers keep completion providers out, and the
  `/` mapping enters the prompt before queued input is processed. `Backspace`
  edits the query and `Esc` always restores normal popup navigation.
- Extended direct compound section editing to placed furniture and project
  templates through unmapped actions in the searchable `?` popup. Furniture
  handles quarter turns and world-space snapping; templates use an isolated
  local canvas preview. Both preserve and validate their explicit anchors. A
  compact save popup explicitly chooses **This item only** or **Item + project
  template**; the latter is one atomic undo step and neither path rewrites
  other placed items. Template changes round-trip through saved project
  catalogues and become defaults for future placements.
- Added a one-line contextual selection breadcrumb to the existing action bar.
  Rooms, furniture, doors, windows, outlets, and project templates use their
  semantic colors and concise owner/object labels; MOVE and RESIZE add active
  direction, distance, edge, section, and snap-target feedback. It introduces
  no mappings or popups, hides without a useful selection, stays bounded in
  wide/medium/compact layouts, and never displaces action hints that previously
  fit.
- Added schema v4 wall/floor outlet placement with a sequential v3-to-v4
  migration. Wall outlets render as half circles pointing into their room;
  floor outlets use full circles and validated room-local positions. The `?`
  action window is searchable with `/`, while the compact Add menu remains
  direct. Zoom now uses adjacent unshifted `,` and `.` keys.
- Kept room size editing in the ordinary `e` form without exposing internal
  part coordinates. A responsive side preview stays out of narrow layouts,
  while `r` starts direct canvas resizing that can select, add, resize, and
  remove valid room sections before committing the whole shape as one undo
  step. Ordinary `m` movement continues to move the room and its furniture
  together and now shows the same snap feedback. Persistent section status,
  named alignment guides, and a strongly highlighted overlap show exactly
  where edges snap; moving away releases the target without trapping fine
  steps. A section now resizes from the west/east or south/north edge chosen by
  the first direction key instead of always anchoring its origin. Normal and
  coarse movement use configured-step multiples large enough to cross one
  visible cell, preventing partial border/label movement at distant zoom;
  fine movement remains exact and the current distance is shown in MOVE status.
  Snap guides now extend just beyond their target wall so north/south support
  lines remain visible as clearly as east/west ones. `s` applies an active
  resize and saves the plan.
- Activated schema v3 with first-class wall windows and typed 1–32-slot
  outlets, sequential v1/v2 migration, wall-aware forms/actions/validation,
  canvas representation, direct `W`/`O` keys, and Add-palette `w`/`o` choices.
- Replaced bracket-based view rotation and issue navigation defaults with
  reachable `Alt-h/l` and `Alt-k/j` directional mappings.
- Added session-local `high`, `middle`, and `none` canvas detail levels for
  exterior-wall, furniture, door, and window dimensions, with `t`, an Ex
  command, a Lua API, and a `middle` default.
- Added direct L-shaped room creation and editing with configurable leg
  dimensions, all four missing-corner orientations, and compact room area,
  perimeter, bounds, and part-count details.
- Activated schema v2 with connected rectangular-union footprints for compound
  rooms, furniture, and project templates; added exact seam-free geometry,
  part-aware doors, migration fixtures, and safe compound rendering/actions.
- Schema-v1/v2/v3 JSON and Norg plans now migrate in memory without changing
  source bytes; the first schema-v4 rewrite requires an explicit save and
  remains protected from autosave and reconciliation shortcuts.
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
