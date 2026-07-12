# Changelog

All notable changes to `roomplan.nvim` will be documented here.

## [Unreleased]

- Initial strict schema-v1 model, JSON codec, metric parser, semantic actions,
  bounded history, geometry, snapping, door swing calculations, and validation.
- Interactive Unicode/ASCII canvas with hit testing, viewport controls,
  inspector, object/issue lists, configurable buffer-local mappings, and menus.
- Default responsive workspace with synchronized Objects/Issues, Canvas and
  Properties panes, a contextual action/status bar, explicit empty/offscreen
  states, and compact drawers for narrow terminals.
- Structured Room, Furniture, Door, Alignment, Plan, Custom Template, and
  geometry-edit forms with conditional fields, normalized measurements,
  inline validation, textual previews, stale-revision guards, atomic
  Apply/Cancel, and explicit invalid-draft policy where supported; the classic
  prompt experience remains available temporarily through configuration.
- Native `j/k`/Enter action palette for `:RoomPlan`, session choice, and the
  non-empty Add menu; custom templates are visible in Objects.
- Centralized semantic/default-lhs mapping overrides across workspace panes,
  Canvas, forms, palettes, contextual actions, and displayed action/form hints.
- Runtime `:RoomPlanAspect [ratio]` calibration for terminal/font cell geometry;
  the canvas refits without changing model data, history, or unrelated options.
- Conflict-safe standalone and Norg persistence, atomic new-file creation,
  Save As destination checks, staged-write recovery, and native quit guards.
- Revision-bound destructive confirmations, retained-model protection after
  failed reloads, symlink-safe Save As checks, and UTF-8 BOM/CRLF round trips.
- Health checks, JSON Schema, fixtures, help, documentation, and a Neovim
  0.10/0.11/0.12.4/nightly plus cross-platform CI matrix.
