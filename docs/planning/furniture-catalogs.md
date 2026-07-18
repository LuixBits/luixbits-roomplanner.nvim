# Furniture catalogues

RoomPlan combines three template sources:

1. generic built-ins such as bed, sofa, chair, table, desk, storage, kitchen,
   appliance, bathroom fixture, and custom rectangle;
2. process-local definitions loaded by `setup()` from Lua or JSON;
3. project-local `custom_templates` saved in the plan.

Imported and project IDs use the `custom:` prefix. `builtin:` IDs are reserved
and cannot be replaced. A project template with the same ID takes precedence
over an imported default for that plan.

## Inline Lua definitions

```lua
require("roomplan").setup({
  furniture = {
    definitions = {
      {
        id = "custom:standing-desk",
        name = "Standing desk",
        category = "work",
        shape = "rectangle",
        default_size_mm = { 1600, 800, 1100 },
      },
    },
  },
})
```

## JSON files

```json
{
  "version": 1,
  "furniture": [
    {
      "id": "custom:meeting-table",
      "name": "Meeting table",
      "category": "work",
      "shape": "rectangle",
      "default_size_mm": [2400, 1200, 750]
    }
  ]
}
```

Load one or more files with paths expanded by Neovim:

```lua
require("roomplan").setup({
  furniture = {
    files = { "~/.config/nvim/roomplan-furniture.json" },
  },
})
```

By default, imported furniture extends RoomPlan's generic catalogue. To make
your files and inline definitions the complete list offered for new furniture,
hide the built-ins:

```lua
require("roomplan").setup({
  furniture = {
    include_builtins = false,
    files = { "~/.config/nvim/roomplan-furniture.json" },
  },
})
```

This changes catalogue choices, not saved data. Reserved `builtin:` IDs remain
resolvable so existing plans do not break when the visible defaults are
replaced. Imported entries continue to use stable `custom:` IDs.

Only the fields above are accepted, only `rectangle` is supported, dimensions
must be positive integer millimetres, and each file is limited to 1 MiB.
Duplicate IDs, unknown fields, malformed files, or invalid definitions make
`setup()` fail atomically; the previous effective catalogue is retained.

Imported definitions are configuration, not plan data. A placed item retains
its explicit geometry, but validation warns if its template ID cannot be
resolved in another installation. Share the JSON file with the project when
stable template identity matters across machines.

Only project-local templates are editable from the plan. Their direct shape
editor changes future placements; a placed item can explicitly update both
itself and its project template from the save-scope popup. Imported and built-in
catalogue definitions remain read-only, and no template edit rewrites other
already placed items.

← [Furniture](furniture.md) | [Documentation home](../README.md) | [Appearance](../display/appearance.md) →
