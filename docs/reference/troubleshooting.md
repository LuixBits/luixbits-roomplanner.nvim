# Troubleshooting

Start with:

```vim
:checkhealth roomplan
```

It checks Neovim compatibility, glyph widths, canvas aspect, keymap overrides,
optional Norg support, autosave, live sessions, and source permissions.

## RoomPlan cannot be required

The error `module 'roomplan' not found` means the plugin is not on
`runtimepath` when your configuration calls `require("roomplan")`.

```vim
:lua print(vim.inspect(vim.api.nvim_get_runtime_file("lua/roomplan/init.lua", false)))
```

The result should contain the installed plugin. Check that your package points
to `LuixBits/luixbits-roomplanner.nvim` and includes
`lua/roomplan/init.lua`. It must load before its setup call.

With lazy loading, use `lazy = false` or declare every RoomPlan command that
may trigger loading. With Nix based managers, add the built Vim plugin package
to the Neovim plugin set. Rebuild that package after changing a local source
path.

## RoomPlan commands are missing

For `E492: Not an editor command: RoomPlan`, check the command loader:

```vim
:lua print(vim.inspect(vim.api.nvim_get_runtime_file("plugin/roomplan.lua", false)))
:lua print(vim.fn.exists(":RoomPlan"))
```

The second value should be `2`. If `:runtime plugin/roomplan.lua` registers the
commands, fix the package load order. The manual command is only a useful test.

## A key does nothing

RoomPlan mappings are local to its own buffers. Some keys also depend on the
focused pane, selected object, or active mode. Press `?` to see actions for the
current context.

Run `:checkhealth roomplan` to inspect disabled mappings and overrides. Press
`2` to return to the Canvas before trying a Canvas action shown in Details.
See [Keymaps](../configuration/keymaps.md) for the current defaults.

## The Canvas looks stretched or empty

- Press `f` if the plan may be outside the viewport.
- Run `:RoomPlanAspect` if squares look too tall or too wide.
- Try `canvas.unicode = "ascii"` if box glyphs have the wrong width.

Fonts and `'ambiwidth'` can affect glyph widths. See
[Aspect and rotation](../display/aspect-and-rotation.md) for calibration.

## Colours or pane borders look inactive

Inspect `:highlight RoomPlanWall` and
`:highlight RoomPlanWorkspaceActiveBorder`. RoomPlan links its groups to
standard colour scheme groups.

If your colour scheme clears custom highlights after startup, reapply your
overrides in a `ColorScheme` autocmd. See
[Appearance](../display/appearance.md).

## A form or popup feels cramped

RoomPlan drops optional previews when the editor is narrow. Increase the
editor size if fields or action text still feel crowded. The plan itself is
not affected.

## Saving or reloading is blocked

- Press `v` and inspect Issues. Layout errors require repair or an explicit
  `:RoomPlanSave!`. Structural errors cannot be forced.
- `CONFLICT` means the source changed outside RoomPlan. Use
  `:RoomPlanResolveConflict` to review the available choices.
- `SOURCE_REBIND_PENDING` means the source buffer was renamed. Use Save As or
  restore the original name.
- If several plans are open, use `:RoomPlan` to choose the intended session.

Do not edit revision hashes to bypass a conflict. They protect newer source
content from an accidental overwrite.

## A Norg plan is not detected

Use one exact marked range:

```norg
@code json roomplan.nvim
{ "format": "roomplan.nvim", ... }
@end
```

RoomPlan stops when it finds multiple marked blocks, malformed JSON, an
unfinished range, or several matching legacy blocks. Repair the ambiguous
content first. Neorg and its parser are not required for the scanner.

← [Lua API](lua-api.md) | [Documentation home](../README.md) | [Limitations and roadmap](limitations-and-roadmap.md) →
