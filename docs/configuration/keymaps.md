# Keymaps

RoomPlan mappings are normal-mode, silent, and buffer-local. Workspace panes,
Canvas, forms, and action windows all use one resolver, so the keys displayed
in the action bar and help follow configuration.

```lua
require("roomplan").setup({
  keymaps = {
    enabled = true,
    mappings = {
      hide = "<leader>q",
      form_apply = "<leader>s",
      ["<C-h>"] = false,
    },
  },
})
```

An override key may be a semantic name or the default left-hand side. Its
value is a replacement left-hand side; `false` disables it. Semantic names are
preferred because they affect only the intended action. Setting
`keymaps.enabled = false` prevents RoomPlan from installing any mappings; use
commands or your own buffer mappings in that case.

## Workspace and selection

| Default | Semantic name | Action |
| --- | --- | --- |
| `Tab` / `Shift-Tab` | `workspace_next_pane` / `workspace_previous_pane` | Cycle panes |
| `1`, `2`, `3`, `!` | `focus_objects`, `focus_canvas`, `focus_properties`, `focus_issues` | Toggle/focus a workspace area |
| `Enter` | `workspace_activate_focused` | Select focused Objects/Issues row |
| `Space` | `workspace_toggle_mark_focused` | Mark/unmark an Objects row for atomic batch actions |
| `/` | `workspace_filter_focused` | Filter Objects or Issues |
| `h` / `l` | `workspace_collapse_focused` / `workspace_expand_focused` | Collapse/expand an Objects room |
| `Enter` | `workspace_toggle_details_section` | Toggle a Details section |
| `a`, `D`, `W`, `O`, `F` | `add`, `add_door`, `add_window`, `add_outlet`, `add_furniture` | Add objects |
| `e`, `d`, `y` | `edit`, `delete`, `duplicate` | Edit supported properties, delete, duplicate |
| `m`, `A` | `move_mode`, `align` | Move room/object, align room |
| `r`, `R` | `resize_dimensions`, `rotate` | Live-resize room/furniture dimensions, rotate furniture |
| `Enter` | `select` | Select under Canvas cursor |
| `q`, `Esc`, `?` | `hide`, `escape`, `help` | Hide, leave context, show actions |

The convenience `o` and `i` keys use semantic names `objects` and `inspector`
for Navigator and Details. `select_next` and `select_previous` name the Canvas
object-cycle mappings when pane cycling is disabled.

The `a` Add menu has its own one-key choices: `r` room, `d` door, `w`
window, `o` outlet, and `f` furniture. Selected windows and outlets use the
ordinary `e`, `m`, `y`, and `d` edit/move/duplicate/delete mappings.

## View, history, and source

| Default | Semantic name | Action |
| --- | --- | --- |
| `v`, `Alt-k`, `Alt-j` | `validate`, `previous_issue`, `next_issue` | Validate/navigate issues |
| `u`, `Ctrl-r` | `undo`, `redo` | Semantic history |
| `f`, `.`, `,` | `fit`, `zoom_in`, `zoom_out` | Fit/zoom |
| `M` | `toggle_minimap` | Show/hide the whole-plan minimap and field-of-view rectangle |
| `t` | `cycle_detail_level` | Cycle `high`, `middle`, and `none` canvas detail |
| `L` | `sun_study` | Open the sunlight study in NAV; remains coarse-right in MOVE/PAN/RESIZE |
| Sun mode: `h`/`l`, `j`/`k` | contextual | Earlier/later time; next/previous three-month season on canvas |
| `Alt-h`, `Alt-l`, `g0` | `rotate_view_counterclockwise`, `rotate_view_clockwise`, `reset_view` | Rotate projection |
| `gs`, `g!` | `toggle_snap`, `bypass_snap` | Snapping controls |
| `s`, `S` | `save`, `save_as` | Save / Save As |

Exact measurement, selected-furniture wall placement, marked-object batch
actions, and named history browsing have no default mapping. They remain
searchable in `?`, and can still receive a semantic override through
`keymaps.mappings` (`measure`, `place_furniture`, `move_marked`,
`duplicate_marked`, `delete_marked`, `clear_marks`, and `history_list`).

Canvas direction keys (`h j k l`, uppercase variants, and Ctrl variants) can be
overridden by their literal default left-hand sides. PAN uses the same keys in
a different mode; `zh zj zk zl` are direct pan aliases. The semantic
`sun_study` override may move or disable the NAV shortcut without removing
uppercase `L` coarse movement from editing modes.

After a study moves to the canvas, contextual `h`/`l` step through time,
`Space` plays or pauses, `L` reopens its popup, and `Esc` closes it. They reuse
existing canvas keys only for the lifetime of the visible study and add no
configuration entries. The dynamic Details controls, footer, and `?` all use
this same resolved mapping data, so an existing override is displayed wherever
the command is documented at runtime.

## Direct compound-shape resizing

Select a room, placed furniture item, or project template and press `r` to
enter the highlighted live resize immediately. The same controls remain
discoverable through **Edit footprint** in the `e` popup, but that popup is not
required. Uppercase `R` rotates selected furniture. There is no duplicate
hidden shape action in `?`; all three object kinds share the controls below.

| Default | Semantic name | Action |
| --- | --- | --- |
| `Enter` | `select` | Select section under the cursor |
| `Tab` / `Shift-Tab` | `shape_next` / `shape_previous` | Cycle shape sections |
| `h j k l` | literal keys | Choose west/south/north/east first, then move that edge by the normal step |
| `H J K L` | literal keys | Resize by the coarse step |
| `Ctrl-h/j/k/l` | literal keys | Resize by the fine step |
| `a` / `d` | `add` / `delete` | Add / remove a section |
| `gs` / `g!` | `toggle_snap` / `bypass_snap` | Toggle snapping / bypass the next change |
| `s` | `save` | Commit the resize and save; project-linked furniture first chooses item or template scope in a popup |
| `Esc` | `escape` | Cancel without changing the model |

## Forms and action windows

| Default | Semantic name | Action |
| --- | --- | --- |
| `Tab` / `Shift-Tab` | `form_next_field` / `form_previous_field` | Change field |
| `Enter` | `form_edit` | Edit/choose field |
| `h` / `l` | `form_previous_choice` / `form_next_choice` | Cycle choice |
| `Space` | `form_toggle` | Toggle field |
| `Ctrl-s` | `form_apply` | Apply atomically |
| `R` | `form_reset` | Reset draft |
| `Esc` | `form_cancel` | Cancel form |
| `j` / `k` | `palette_next` / `palette_previous` | Move in a palette |
| `Enter` / `Esc` | `palette_choose` / `palette_cancel` | Run/cancel palette |
| `/` | `palette_search` | Start live search in the full `?` action window |

Search is deliberately limited to the full action window opened by `?`. The
search prompt and filtered results remain inside that popup. A dedicated native
prompt owns input while the fixed-size results window stays read-only, so
filter redraws cannot move the cursor and completion providers stay disabled.
`Backspace` removes a character. The small `a` Add menu keeps immediate one-key
choices and does not expose search.

The Sun Study is also a structured popup. Inside it, `h`/`l` step backward or
forward and `Space` plays or pauses; its ordinary form keys still edit fields,
apply, and cancel.

Run `:checkhealth roomplan` to review overrides, explicitly disabled actions,
and duplicate replacement keys.

← [Settings](settings.md) | [Documentation home](../README.md) | [Commands](../reference/commands.md) →
