# ADR-0005: Interaction is popup-first and registry-driven

- Status: Accepted
- Date: 2026-07-19
- Deciders: RoomPlan maintainers

## Context

RoomPlan has many contextual actions but should remain keyboard-first and avoid
a growing set of mandatory global mappings. Command-line prompts obscure the
canvas, provide weak validation, and have previously caused focus problems.
Labels and shortcuts can also drift when panes, footers, help, and menus define
the same action independently.

## Decision

Use structured floating forms for multi-field edits and keep their apply,
cancel, validation, and focus behavior atomic. Use the action registry as the
authority for contextual labels, semantic mappings, availability, handlers,
and disabled reasons. The footer, Details controls, and searchable `?` palette
consume that registry.

Prefer contextual or buffer-local keys over new globals. Keep analysis,
viewport, pane, filter, form, and preview state transient unless persistence is
part of the user model. Use `vim.ui` only for small scalar or choice handoffs so
providers can enhance them without becoming dependencies.

## Alternatives considered

- **Expose every action as a global mapping:** rejected because it creates
  collisions and an unlearnable default surface.
- **Use command-line input for forms:** rejected because it hides context and
  cannot show coherent draft validation.
- **Maintain separate pane/menu key definitions:** rejected because displayed
  hints and installed mappings would drift.
- **Require one UI framework:** rejected to preserve a dependency-free core.

## Consequences

### Positive

- Actions remain discoverable without consuming many keys.
- Mapping overrides update visible hints consistently.
- Popup edits can validate, preview, cancel, and restore focus as one workflow.

### Costs and constraints

- Focus ownership and narrow-screen layout require explicit regression tests.
- New contextual actions must integrate with the registry rather than create a
  parallel menu.
- Standard `vim.ui` fallback may still use command-line input for the few
  delegated scalar editors.

## Verification

Form, palette, action-registry, workspace, focus, and compact-layout tests
exercise interaction and mapping consistency.

## Related material

- [Forms and actions](../workspace/forms-and-actions.md)
- [Keymaps](../configuration/keymaps.md)
- [Architecture](../development/architecture.md)
