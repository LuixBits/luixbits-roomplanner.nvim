# Contributing

Read `plan.md` before changing persistence, geometry, or lifecycle behavior.
Keep model, schema, actions, geometry, validation, scene extraction, and the
logical rasterizer independent of Neovim wherever their module contract says
so. All user-visible model mutations must be semantic actions with tests.

Run `scripts/test.sh` before submitting changes. Update snapshots only after
reviewing their semantic diff. A schema version change requires a sequential
migration, fixtures, JSON Schema changes, and recovery documentation.

Do not copy Neorg implementation code. Any adapted third-party code must keep
its license notice and be recorded in `NOTICE` before merge.

## Extension points

- Built-in furniture belongs in `lua/roomplan/catalog.lua`. Keep entries
  generic, return defensive copies, use `builtin:*` IDs, and add catalogue plus
  placement/round-trip tests. Project-specific entries belong in the plan's
  `custom_templates`, not the global catalogue.
- A storage adapter must implement detection-independent `load`, `serialize`,
  `prepare_save`, `commit`, and `initialize` boundaries, return structured
  errors, compare an expected content revision immediately before mutation,
  and be registered in `lua/roomplan/storage/init.lua`. Never evaluate source
  content or overwrite malformed/ambiguous data.
- New geometry operations stay in pure Lua under `lua/roomplan/geometry/` and
  use integer or doubled-integer predicates. Add negative-coordinate,
  tangency, large-origin, and deterministic-tie tests before exposing an
  action.
- Renderable concepts first become semantic scene primitives. The rasterizer
  remains bounded by viewport cells, keeps hit provenance separate from
  glyphs, and must preserve Unicode byte/display-column safety. Add ASCII and
  Unicode snapshot/hit tests.
- Every persisted mutation goes through `actions.apply`; controllers add one
  history node only after one successful action. UI code may mutate selection
  and viewport state, never nested model tables.

Run `./scripts/test.sh`, `:checkhealth roomplan`, and `:helptags doc` before a
release change. Persistence/lifecycle changes should include a recovery or
conflict regression, not only a happy-path unit test.
