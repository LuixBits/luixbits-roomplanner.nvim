# RoomPlan documentation

Start with the guide that matches what you are trying to do. The [complete
chapter list](SUMMARY.md) is available if you prefer to read the handbook in
order.

## New to RoomPlan

1. [Install RoomPlan](getting-started/installation.md).
2. [Build your first plan](getting-started/quick-start.md).
3. [Learn how plans, sources, sessions, and workspaces differ](getting-started/concepts.md).

The quick start creates two rooms, connects them with a door, adds furniture
and wall features, validates the result, and saves it.

## Find a task

| I want to... | Read |
| --- | --- |
| Create, move, resize, or align a room | [Rooms](planning/rooms.md) |
| Add or edit furniture | [Furniture](planning/furniture.md) |
| Import furniture defaults | [Furniture catalogues](planning/furniture-catalogs.md) |
| Add a door between rooms or to the outside | [Doors](planning/doors.md) |
| Add a window or outlet | [Windows and outlets](planning/windows-and-outlets.md) |
| Measure a gap or place furniture against a wall | [Forms and actions](workspace/forms-and-actions.md) |
| Zoom, pan, rotate, or use the minimap | [Canvas](workspace/canvas.md) |
| Compare approximate sunlight exposure | [Sun study](planning/sun-study.md) |
| Change a key | [Keymaps](configuration/keymaps.md) |
| Change colours or glyphs | [Appearance](display/appearance.md) |
| Correct a stretched canvas | [Aspect and rotation](display/aspect-and-rotation.md) |
| Understand a blocked save | [Validation](data/validation.md) |
| Recover from a source conflict | [Storage and sessions](data/storage-and-sessions.md) |
| Diagnose an installation or display problem | [Troubleshooting](reference/troubleshooting.md) |

## Learn the workspace

- [Workspace overview](workspace/overview.md)
- [Navigation and interaction modes](workspace/navigation.md)
- [Navigator, Issues, and Details](workspace/panels.md)
- [Forms and contextual actions](workspace/forms-and-actions.md)
- [Canvas controls](workspace/canvas.md)

## Configure RoomPlan

- [Settings](configuration/settings.md)
- [UI providers](configuration/ui-providers.md)
- [Keymaps](configuration/keymaps.md)
- [Appearance, highlights, and glyphs](display/appearance.md)
- [Aspect calibration and view rotation](display/aspect-and-rotation.md)

## Plan data and saving

- [Storage, sessions, migration, and conflicts](data/storage-and-sessions.md)
- [Validation and repair drafts](data/validation.md)
- [Coordinates and document schema](data/coordinates-and-schema.md)

## Reference

- [Commands](reference/commands.md)
- [Lua API](reference/lua-api.md)
- [Troubleshooting](reference/troubleshooting.md)
- [Limitations and roadmap](reference/limitations-and-roadmap.md)

Inside Neovim, `:help roomplan` provides the offline reference and
`:checkhealth roomplan` checks compatibility, configuration, mappings,
display, sessions, and source access.

## Development

- [Architecture](development/architecture.md)
- [Compatibility policy](development/compatibility.md)
- [Architecture decisions](adr/README.md)
- [Contributing](../CONTRIBUTING.md)
- [Release checklist](../RELEASE.md)

The root contribution and release documents are authoritative. The other
development chapters explain the architecture and compatibility boundaries
around those procedures.
