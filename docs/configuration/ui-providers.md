# UI providers

[← Settings](settings.md) · [Documentation home](../README.md) · [Next: Keymaps →](keymaps.md)

RoomPlan works without another UI plugin. It owns the workspace, structured
forms, and action windows. Small text fields and confirmation choices use
Neovim's standard `vim.ui.input` and `vim.ui.select` interfaces.

A provider can replace those transient prompts without taking over RoomPlan's
panels or becoming a RoomPlan dependency. With no provider, Neovim may show
text input on the command line.

## Snacks example

If Snacks is already part of your configuration, its input, picker, and
notifier modules can provide floating input, searchable choices, and
notifications:

```lua
{
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    input = { enabled = true },
    picker = { enabled = true, ui_select = true },
    notifier = { enabled = true },
  },
}
```

Use one input/select provider and load it before starting an interactive
RoomPlan workflow. If several plugins replace the same `vim.ui` function, the
last provider loaded wins.

## Integration hints

RoomPlan supplies standard input `scope` hints and stable selection `kind`
hints. Providers may use or ignore them.

The named kinds are `roomplan_form_choice`,
`roomplan_furniture_template`, `roomplan_color`, `roomplan_confirmation`,
`roomplan_conflict_resolution`, and `roomplan_norg_heading`. Other RoomPlan
choices use `roomplan_selection`.

[← Settings](settings.md) · [Documentation home](../README.md) · [Next: Keymaps →](keymaps.md)
