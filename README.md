# roomplan.nvim

A keyboard-first floor-planning workspace for Neovim.

RoomPlan keeps exact millimetre geometry in structured JSON or an embedded
Neorg block. The Unicode/ASCII canvas is an interactive view, so display
rounding can never corrupt the saved plan.

> RoomPlan is a space-planning tool, not CAD/BIM software or a building-code
> checker. The current schema models one floor with rectangular-union room and
> furniture footprints, doors, windows, wall/floor outlets, and 90-degree furniture
> rotations.

## Highlights

- Canvas-first responsive workspace with toggleable Navigator and Details
  panes, contextual actions, a compact selection/MOVE/RESIZE breadcrumb,
  validation issues, semantic highlighting, and a north compass. Three
  transient detail levels keep labels and measurements as sparse or complete
  as the current task needs.
- Structured forms for rooms, furniture, doors, windows, outlets, alignment,
  plan settings, and project furniture templates, including palette-based room
  and furniture colors.
- Compound footprints for L-, T-, and U-shaped rooms and furniture, with
  seam-free walls and one logical selection per object. The room form creates
  configurable L shapes; direct canvas resizing can add, resize, and remove
  rectangular room sections.
- View-only 90-degree rotation and runtime terminal-cell aspect calibration;
  neither operation changes saved geometry.
- Strict, deterministic JSON with preserved extension fields, plus marked Neorg
  embedding and conflict-safe writes.
- Undo/redo, snapping, validation, bounded resources, multiple concurrent
  plans, and dirty-session protection.
- Dependency-free furniture catalogues from inline Lua definitions or JSON
  files.
- No mandatory runtime dependency beyond Neovim 0.10 or newer. Standard
  `vim.ui` providers such as Snacks work automatically when configured.

## Install

With lazy.nvim:

```lua
{
  "LuixBits/luixbits-roomplanner.nvim",
  lazy = false,
  main = "roomplan",
  opts = {},
}
```

With Neovim 0.12 `vim.pack`:

```lua
vim.pack.add({
  { src = "https://github.com/LuixBits/luixbits-roomplanner.nvim" },
})

require("roomplan").setup({})
```

For Nix, nvf, rocks.nvim, native packages, and local development, see the
[installation chapter](docs/getting-started/installation.md). Keep the plugin
available on `runtimepath` before calling `require("roomplan")`; this is what
prevents the `module 'roomplan' not found` and missing `:RoomPlan` command
errors common to incomplete lazy/Nix wiring.

## First plan

Initialize a standalone source without overwriting an existing file:

```vim
:RoomPlanInit ~/plans/flat.roomplan.json
```

Then press `a` to add a room, `m` to move the selected room and its furniture,
`r` to resize its sections, or `e` for exact properties. Save with `s`. Press
`t` to cycle canvas detail, `1` to focus or toggle the
Navigator, and `3` to do the same for Details. `?` opens every currently
available action; press `/` there to search it. `,` and `.` zoom out and in.
`q` returns to the canvas before hiding the workspace. Add a window directly
with `W` or an outlet with `O`; the outlet form chooses wall or floor placement.
From the Add menu use `a` followed by lowercase `w` or `o`.

Open the plan again with:

```vim
:RoomPlanOpen ~/plans/flat.roomplan.json
```

The [quick-start chapter](docs/getting-started/quick-start.md) walks through a
complete room, furniture, door, window, and outlet workflow.

## Documentation

The documentation is a linked, chaptered handbook:

- [Documentation home](docs/README.md) and [complete chapter list](docs/SUMMARY.md)
- [Workspace and navigation](docs/workspace/overview.md)
- [Rooms](docs/planning/rooms.md), [doors](docs/planning/doors.md),
  [windows and outlets](docs/planning/windows-and-outlets.md), and
  [furniture](docs/planning/furniture.md)
- [Settings](docs/configuration/settings.md),
  [keymaps](docs/configuration/keymaps.md), and
  [appearance](docs/display/appearance.md)
- [Aspect calibration and rotation](docs/display/aspect-and-rotation.md)
- [Storage and sessions](docs/data/storage-and-sessions.md),
  [validation](docs/data/validation.md), and
  [document schema](docs/data/coordinates-and-schema.md)
- [Commands](docs/reference/commands.md), [Lua API](docs/reference/lua-api.md),
  and [troubleshooting](docs/reference/troubleshooting.md)
- [Architecture](docs/development/architecture.md),
  [contributing](docs/development/contributing.md), and
  [releasing](docs/development/releasing.md)

Inside Neovim, `:help roomplan` is the compact offline reference and
`:checkhealth roomplan` reports compatibility, display, mappings, optional
Neorg support, sessions, and source safety.

## Configuration example

Defaults work without `setup()`. A small customized configuration looks like:

```lua
require("roomplan").setup({
  canvas = {
    cell_aspect = 2.0,
    show_grid = false,
    detail_level = "middle",
    show_compass = true,
  },
  furniture = {
    include_builtins = false,
    files = { vim.fn.stdpath("config") .. "/roomplan-furniture.json" },
  },
  ui = {
    workspace = {
      navigator_visible = true,
      details_visible = false,
      border = "rounded",
    },
  },
})
```

RoomPlan rejects unknown or invalid options instead of silently ignoring them.
See [settings](docs/configuration/settings.md) for the complete contract.

## Development

Run the headless test suite from the repository root:

```sh
./scripts/test.sh
```

Contribution rules and release gates live in
[CONTRIBUTING.md](CONTRIBUTING.md) and [RELEASE.md](RELEASE.md). The design and
dependency boundaries are maintained in the
[architecture chapter](docs/development/architecture.md), not in historical
implementation-plan files.

## License

Licensed under the GNU General Public License v3.0 only (`GPL-3.0-only`). See
[LICENSE](LICENSE). You may use, study, modify, and redistribute RoomPlan, but
distributed versions must preserve the same freedoms and provide their source.
Third-party material, if introduced, must also be recorded in [NOTICE](NOTICE).
