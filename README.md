# roomplan.nvim

[![CI](https://github.com/LuixBits/luixbits-roomplanner.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/LuixBits/luixbits-roomplanner.nvim/actions/workflows/ci.yml)
[![License: GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-blue.svg)](LICENSE)

A keyboard-first floor planner for Neovim.

RoomPlan stores measurements as structured millimetre geometry. The terminal
canvas is an interactive view of that data. Display rounding cannot change the
saved plan.

RoomPlan is intended for space planning. It is not CAD, BIM, a construction
drawing tool, or a building-code checker.

## What it does

- Create rectangular or compound rooms and furniture.
- Add doors, windows, wall outlets, and floor outlets.
- Move, resize, rotate, align, measure, and validate objects from the canvas.
- Import furniture catalogues from Lua or JSON.
- Save plans as standalone JSON or inside a marked Norg block.
- Inspect sunlight exposure with an offline two-dimensional study.
- Keep several plans open with undo history and conflict-safe saving.

RoomPlan supports Neovim 0.10 and newer. It has no required runtime dependency.

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

See [Installation](docs/getting-started/installation.md) for Nix, nvf,
rocks-git.nvim, native packages, and local development.

## Create a plan

Create a standalone plan:

```vim
:RoomPlanInit ~/plans/flat.roomplan.json
```

The most useful default keys are:

| Key | Action |
| --- | --- |
| `a` | Add an object |
| `e` | Edit exact properties |
| `m` | Move the selected object |
| `r` | Resize a room or furniture item |
| `R` | Rotate furniture |
| `s` | Save |
| `u` / `Ctrl-r` | Undo / redo |
| `.` / `,` | Zoom in / out |
| `1` / `2` / `3` | Navigator / Canvas / Details |
| `?` | Show all actions for the current context |

Press `/` inside the `?` window to search its actions. The [Quick
start](docs/getting-started/quick-start.md) builds a complete plan with rooms,
furniture, a door, a window, and an outlet.

Open an existing plan with:

```vim
:RoomPlanOpen ~/plans/flat.roomplan.json
```

## Documentation

Start at the [documentation home](docs/README.md) when you need help with a
specific task.

- [Installation](docs/getting-started/installation.md)
- [Quick start](docs/getting-started/quick-start.md)
- [Default keys and remapping](docs/configuration/keymaps.md)
- [Rooms](docs/planning/rooms.md) and [furniture](docs/planning/furniture.md)
- [Doors](docs/planning/doors.md), [windows and outlets](docs/planning/windows-and-outlets.md)
- [Sun study](docs/planning/sun-study.md)
- [Saving, sessions, and conflicts](docs/data/storage-and-sessions.md)
- [Troubleshooting](docs/reference/troubleshooting.md)

Inside Neovim, use `:help roomplan` for the offline reference and
`:checkhealth roomplan` for diagnostics.

## Configuration

Defaults work without calling `setup()`. RoomPlan validates all supplied
options and rejects unknown settings.

See [Settings](docs/configuration/settings.md),
[Keymaps](docs/configuration/keymaps.md), and
[Appearance](docs/display/appearance.md) for the complete configuration.

## Development

Run the test suite from the repository root:

```sh
./scripts/test.sh
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing the project. Release
requirements are in [RELEASE.md](RELEASE.md). The [architecture
chapter](docs/development/architecture.md) describes the code boundaries.

Use [SUPPORT.md](SUPPORT.md) for questions and bug reports. Report security
issues as described in [SECURITY.md](SECURITY.md).

## License

RoomPlan is licensed under GPL-3.0-only. See [LICENSE](LICENSE). Distributed
versions must remain under the same license and provide their source.
Third-party notices are recorded in [NOTICE](NOTICE).
