# Troubleshooting

Start with:

```vim
:checkhealth roomplan
```

It reports Neovim/runtime compatibility, encoding, glyph widths, cell aspect,
keymap overrides, optional Norg support, autosave, live sessions, and source
writability.

## `module 'roomplan' not found`

This means the repository root is not on `runtimepath` when your configuration
calls `require("roomplan")`; it is not a plan-file or UI error.

```vim
:lua print(vim.inspect(vim.api.nvim_get_runtime_file("lua/roomplan/init.lua", false)))
```

The result must contain the installed plugin. Check that the package points at
`LuixBits/luixbits-roomplanner.nvim`, contains `lua/roomplan/init.lua`, and is
loaded before its setup call. With lazy loading, either use `lazy = false` or
declare every RoomPlan command that can trigger loading. With Nix/nvf/mnw, add
the built Vim plugin package—not merely the raw flake input—to the Neovim
plugin set. A Nix store build must be rebuilt after changing a local source
path; a normal non-Nix checkout does not.

## `E492: Not an editor command: RoomPlan`

The command loader `plugin/roomplan.lua` was not sourced. Check:

```vim
:lua print(vim.inspect(vim.api.nvim_get_runtime_file("plugin/roomplan.lua", false)))
:lua print(vim.fn.exists(":RoomPlan"))
```

The second value should be `2`. `require("roomplan").setup({})` also registers
commands once the package is available. For diagnosis,
`:runtime plugin/roomplan.lua` should register them; if it does, fix package
load order rather than keeping the manual runtime command.

## Canvas looks stretched or misaligned

- If squares are too tall/short, calibrate `:RoomPlanAspect` and persist
  `canvas.cell_aspect`; see [Aspect and rotation](../display/aspect-and-rotation.md).
- If box glyphs occupy the wrong width, try `canvas.unicode = "ascii"` and
  inspect `:checkhealth roomplan`. Fonts and `'ambiwidth'` can change widths.
- If geometry appears absent, press `f`. The canvas distinguishes an empty plan
  from geometry outside the viewport.

## No colors or inactive-looking panes

Inspect `:highlight RoomPlanWall` and
`:highlight RoomPlanWorkspaceActiveBorder`. RoomPlan links semantic groups to
standard colorscheme groups. A colorscheme that clears custom highlights after
startup should reapply overrides in a `ColorScheme` autocmd. See
[Appearance](../display/appearance.md).

## Saving or reloading is blocked

- Press `v` and inspect Issues. Layout errors require repair or an explicit
  `:RoomPlanSave!`; structural errors cannot be forced.
- `CONFLICT` means the source changed since RoomPlan's expected revision. Use
  `:RoomPlanResolveConflict`; do not edit revision hashes or bypass checks.
- `SOURCE_REBIND_PENDING` means the source buffer was renamed. Use Save As to
  adopt a supported destination or restore the original name.
- An ambiguous session means several plans are open outside an attached
  RoomPlan buffer. Use `:RoomPlan` to choose one.

## Norg plan is not detected

Use an exact marked range:

```norg
@code json roomplan.nvim
{ "format": "roomplan.nvim", ... }
@end
```

RoomPlan deliberately stops on multiple marked blocks, malformed marked JSON,
unterminated ranges, or several matching legacy blocks. Repair or remove the
ambiguous block; Neorg and its parser are not required for the scanner.

← [Lua API](lua-api.md) | [Documentation home](../README.md) | [Limitations and roadmap](limitations-and-roadmap.md) →
