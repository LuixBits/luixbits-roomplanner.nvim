# Changelog

All notable changes to `roomplan.nvim` will be documented here.

## [Unreleased]

- Added a non-focusable `M` minimap and `:RoomPlanMinimap`. It reuses the real
  compound-room renderer and configured glyphs, applies subdued room colors,
  and tracks the exact canvas field of view through zoom, pan, scrolloff,
  rotation, edits, and resizing. It adds no plan fields, history, or setup keys
  and never takes keyboard focus.
- Replaced the furniture form's sampled `#` silhouette with a miniature
  RoomPlan canvas. The companion and compact fallback previews now use the
  real footprint fitter, configured cell aspect and glyph set, exact color
  spans, compound parts, dimensions, and live rotation without adding model
  drafts or configuration keys.
- Prevented workspace resize/reflow from stealing focus from active forms,
  palettes, `vim.ui` providers, or unrelated editor windows. Structured forms
  also restore their own focus after cycling choices, rendering companion
  previews, and returning from asynchronous scalar or choice editors.
- Added two pre-release workspace refinements without mappings or saved-plan
  keys. Add and Edit furniture now show a live, colorscheme-linked footprint
  silhouette beside the popup when space permits, with an in-popup compact
  fallback. Invalid input removes stale geometry, and previews never enter IDs,
  validation, history, or persistence. Activating an Issues row or using
  previous/next issue now selects, reveals, and centres its owning object while
  preserving the current zoom and view rotation.
- Restored the in-popup action search on Neovim 0.10 and 0.11 by reading its
  native prompt buffer through the stable buffer API instead of the
  Neovim-0.12-only `prompt_getinput()` function. The required CI matrix keeps
  exercising the same focus and live-filtering regressions on every supported
  Neovim release, and CI checkout now uses the maintained Node 24 action.
- Expanded the offline sun study without adding saved-plan keys. `h`/`l` now
  inspect time while canvas `j`/`k` compare the same clock time three months
  apart. In the `L` popup, `j`/`k` retain ordinary field navigation;
  popup presets cover today, equinoxes, and solstices. Whole-day playback
  reliably rewinds to sunrise, handles fractional sunset boundaries, and ends
  on a transient five-band daily-exposure map. Details adds a timeline,
  progress, fixed UTC-offset reminder, legend, and selected room/window span;
  instant patches now warm with low solar elevation and the header shows the
  incoming-light direction.
- Details now opens with a dynamic NAV/MOVE/PAN/RESIZE/SUN STUDY heading and
  one registry-backed Canvas controls section. The same configured commands
  feed Details, the footer, and `?`; every active mode names its finish or
  cancel key. When Details is visible, the footer keeps status, selection,
  snapping, and zoom without repeating the command list. No setup mappings or
  saved-plan keys were added.
- Sun-study playback now dismisses its setup form and focuses the unobstructed
  canvas. Contextual `h`/`l`, `Space`, `L`, and `Esc` controls step, play/pause,
  reopen settings, and close the overlay. The hidden quit guard now keeps a
  conflicted plan protected while opening the normal conflict-resolution flow
  instead of exposing a Lua callback traceback.
- Added a complete offline sunlight study. `L`, `:RoomPlanSunStudy`, and the
  searchable action popup open one structured workflow for exact plan north,
  location, fixed UTC offset, date/time, step size, frame duration, and
  sunrise-to-sunset playback. Exterior sun-facing walls/windows and clipped
  yellow-to-orange floor patches render beneath normal plan geometry. Windows
  may store one optional sill/head pair or use configurable 900/2100 mm
  defaults without redundant saved keys. Site data is undoable and persisted;
  playback and overlays are transient and timer-safe. User-facing wall choices
  now follow the current top/right/bottom/left view while the stable file
  coordinate schema remains unchanged.
- Made the main canvas responsive to zoom density. Room and furniture names
  now use their projected footprint as a text budget, preserve both ends when
  abbreviated, and disappear once the object is only an overview glyph.
  Dimensions require breathing room around their projected edge, outlet text
  drops out at far zoom, and adjacent labels reserve a separating cell.
- Decoupled exact touch highlighting from magnetic snapping. Movement and live
  resize now recompute every final horizontal and vertical wall contact even
  when snapping is disabled or bypassed. Pure contacts draw only the strong
  touched segments; an actual magnetic correction additionally draws its light
  alignment guide.
- Reworked movement and resize snapping around exact compound silhouettes.
  After one correction, every positive-length room/furniture wall contact is
  retained and highlighted instead of only the winning edge; coincident guide
  lines are deduplicated without dropping their separate overlap segments.
  Centre targets no longer masquerade as wall contact. At deep zoom the plan's
  existing fine step provides a magnetic tolerance floor, capped by the
  existing maximum, so millimetre residuals clean up without a new setting.
- Added popup-first exact clearance measurement and selected-furniture wall
  placement to the searchable `?` window. Measurement updates derived gaps and
  the closest canvas path without editing the plan. Wall placement chooses an
  exact exterior segment, alignment, and clearance, then applies one undoable
  move.
- Added transient Navigator marking with pane-local `Space` and atomic group
  move, duplicate, delete, and clear actions in `?`. Group movement preserves
  spacing, batch changes create one named history entry, and one Undo restores
  the whole set. Also added a searchable named history browser with saved/current
  markers and confirmed restore to any retained revision.
- Unified room, furniture, and project-template shape editing under the
  ordinary `e` popup. Each editor now has an explicit **Edit footprint** row
  that transitions to the shared canvas section controls without a duplicate
  hidden action in `?`. Any changed scalar fields are
  validated and applied before the transition, so popup work is not silently
  discarded. Lowercase `r` now starts the same highlighted live resize for
  rooms, placed furniture, and project templates; uppercase `R` rotates
  furniture.
- Added Neovim-style canvas edge following for NAV movement. `h/j/k/l` and
  their coarse variants keep advancing through world space when the logical
  cursor reaches the edge of a zoomed viewport; the canvas pans just enough to
  preserve the configured `canvas.scrolloff` margin. The default is three
  cells, zero waits for the actual edge, and the transient movement never
  changes plan data or history.
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
  templates through **Edit footprint** in their ordinary `e` popup. Furniture
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
