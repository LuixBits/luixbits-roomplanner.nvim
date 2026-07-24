# Keymaps

RoomPlan installs normal-mode mappings only in its own buffers. The action bar,
Details, and the `?` window show the resolved keys for the current context.

## Canvas

| Key | Action |
| --- | --- |
| `h j k l` | Move the cursor or the active object |
| `H J K L` | Move by the coarse step |
| `Ctrl-h/j/k/l` | Move by the exact fine step |
| `Enter` | Select under the cursor |
| `Tab` / `Shift-Tab` | Cycle workspace panes |
| `a` | Open the Add menu |
| `D` / `W` / `O` / `F` | Add a door, window, outlet, or furniture |
| `e` | Edit exact properties |
| `m` | Move the selection |
| `r` | Resize a room, furniture item, or project template |
| `R` | Rotate furniture |
| `A` | Align a room |
| `d` / `y` | Delete / duplicate |
| `p` | Enter PAN mode |
| `u` / `Ctrl-r` | Undo / redo |
| `U` | Redo convenience alias |
| `v` | Validate and open Issues |
| `Alt-j` / `Alt-k` | Next / previous issue |
| `f` or `zf` | Fit the plan |
| `.` / `,` | Zoom in / out |
| `M` | Toggle the minimap |
| `t` | Cycle canvas detail |
| `S` | Open or reopen the sun study |
| `Alt-l` / `Alt-h` | Rotate the view clockwise / counter-clockwise |
| `g0` | Restore plan view/up |
| `zh zj zk zl` | Pan without entering PAN mode |
| `gs` / `g!` | Toggle snapping / bypass the next snap |
| `s` / `gS` | Save / Save As |
| `?` | Show all actions for the current context |
| `Esc` | Leave the current interaction |
| `q` | Hide the workspace |

The `a` menu uses one-key choices: `r` for Room, `d` for Door, `w` for
Window, `o` for Outlet, and `f` for Furniture.

Exact measurement, furniture wall placement, marked-object actions, and undo
history browsing have no default Canvas key. Find them in `?`.

## Workspace panes

| Key | Action |
| --- | --- |
| `1` or `o` | Toggle or focus Navigator |
| `2` | Focus Canvas |
| `3` or `i` | Toggle or focus Details |
| `!` | Toggle or focus Issues |
| `Tab` / `Shift-Tab` | Cycle visible panes |
| `j` / `k` | Move through rows |
| `Enter` | Select an Objects or Issues row |
| `Space` | Mark or unmark an Objects row |
| `/` | Filter Objects or Issues |
| `h` / `l` | Collapse / expand an Objects room |

In Details, `Enter` or `Space` toggles a section. Use `h` and `l` to collapse
or expand it. Press `2` before using a Canvas command shown in Details.

When `ui.workspace.cycle_tabs` is disabled, `Tab` and `Shift-Tab` use the
`select_next` and `select_previous` mappings to cycle Canvas objects instead.

## Forms

| Key | Action |
| --- | --- |
| `j` / `k` | Next / previous field |
| `Tab` / `Shift-Tab` | Next / previous field |
| `Enter` or `e` | Edit the active field |
| `h` / `l` | Previous / next choice |
| `Space` | Toggle or advance a choice |
| `Ctrl-s` | Validate and apply the draft |
| `R` | Reset the draft |
| `?` | Show actions for the form |
| `q` or `Esc` | Cancel |

## Action windows

| Key | Action |
| --- | --- |
| `j` / `k` | Move through actions |
| `Enter` | Run the selected action |
| `/` | Search the full `?` action window |
| `q` or `Esc` | Close the window |

The small Add menu keeps its one-key choices and has no search. In the full
action window, `/` opens a prompt inside the popup. `Backspace` edits the
query. `Enter` runs the first match. `Esc` returns to the filtered results.

## Live resizing

Select a room, furniture item, or project template and press `r`.

| Key | Action |
| --- | --- |
| `Enter` | Select the section under the cursor |
| `Tab` / `Shift-Tab` | Select the next / previous section |
| `h j k l` | Choose and move an edge by the normal step |
| `H J K L` | Resize by the coarse step |
| `Ctrl-h/j/k/l` | Resize by the fine step |
| `a` / `d` | Add / remove a section |
| `gs` / `g!` | Toggle snapping / bypass the next snap |
| `s` | Apply the resize and save |
| `Esc` | Cancel the resize |

Uppercase `L` always means coarse movement to the right. Uppercase `R` rotates
furniture. Uppercase `S` opens the sun study.

## Sun study

Press `S` to open the study. Inside its form, `h` and `l` change the time.
`Space` starts playback and moves focus to the Canvas. `Ctrl-s` applies the
form and does the same.

While the study is visible on the Canvas:

| Key | Action |
| --- | --- |
| `h` / `l` | Earlier / later time |
| `k` / `j` | Previous / next three-month season |
| `Space` | Start, pause, or resume playback |
| `S` | Reopen the study form |
| `Esc` | Close the study |

## Change a mapping

Use a semantic name when possible. This changes only the intended action.

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

An override value is a replacement left-hand side. Use `false` to disable one
mapping. `keymaps.enabled = false` disables all RoomPlan mappings.

The main semantic names are:

| Area | Semantic names |
| --- | --- |
| Workspace | `workspace_next_pane`, `workspace_previous_pane`, `focus_objects`, `focus_canvas`, `focus_properties`, `focus_issues`, `objects`, `inspector` |
| Rows | `workspace_activate_focused`, `workspace_toggle_mark_focused`, `workspace_filter_focused`, `workspace_collapse_focused`, `workspace_expand_focused`, `workspace_toggle_details_section` |
| Selection | `add`, `add_door`, `add_window`, `add_outlet`, `add_furniture`, `edit`, `move_mode`, `resize_dimensions`, `rotate`, `align`, `duplicate`, `delete`, `select`, `select_next`, `select_previous` |
| Shape editing | `shape_next`, `shape_previous` |
| View | `pan_mode`, `fit`, `zoom_in`, `zoom_out`, `toggle_minimap`, `cycle_detail_level`, `sun_study`, `rotate_view_clockwise`, `rotate_view_counterclockwise`, `reset_view`, `toggle_snap`, `bypass_snap` |
| History and source | `undo`, `redo`, `save`, `save_as`, `validate`, `next_issue`, `previous_issue`, `help`, `hide`, `escape` |
| Forms | `form_next_field`, `form_previous_field`, `form_edit`, `form_previous_choice`, `form_next_choice`, `form_toggle`, `form_apply`, `form_reset`, `form_cancel` |
| Action windows | `palette_next`, `palette_previous`, `palette_choose`, `palette_cancel`, `palette_search` |

The less frequent actions `measure`, `place_furniture`, `move_marked`,
`duplicate_marked`, `delete_marked`, `clear_marks`, `history_list`, `aspect`,
`reload`, and `close` can also receive mappings.

Direction keys use their literal left-hand sides. Uppercase `L` also has the
semantic name `coarse_right`. The literal `U` and literal `zf` aliases can be
moved or disabled by their left-hand sides.

Run `:checkhealth roomplan` to inspect overrides, disabled actions, and
duplicate keys.

← [Settings](settings.md) | [Documentation home](../README.md) | [Commands](../reference/commands.md) →
