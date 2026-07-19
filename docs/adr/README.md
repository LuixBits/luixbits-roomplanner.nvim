# Architecture decision records

Architecture decision records (ADRs) preserve why RoomPlan made durable,
cross-cutting choices. The [architecture chapter](../development/architecture.md)
describes the current system; ADRs record the context, alternatives, and
consequences behind that system.

Create an ADR when a decision is expensive to reverse, affects several layers,
changes a public compatibility boundary, or constrains future implementation.
Ordinary feature details and temporary implementation plans belong in tests,
the handbook, issues, or [`plan.md`](../../plan.md), not in an ADR.

## Process

1. Copy [0000-template.md](0000-template.md) to the next four-digit number.
2. Use a short kebab-case title and start with status **Proposed**.
3. Discuss alternatives and migration/recovery consequences before acceptance.
4. Change the status to **Accepted** when the decision is merged.
5. Never rewrite an accepted decision to describe a new direction. Add a new
   ADR that marks the old one **Superseded by ADR-NNNN**.

ADRs are immutable history apart from spelling, links, and explicit status
changes. Their consequences are enforced by code review and tests where
practical.

## Index

- [ADR-0001: Exact authored geometry is independent of terminal rendering](0001-exact-geometry-and-terminal-rendering.md)
- [ADR-0002: Semantic actions are the model mutation boundary](0002-semantic-actions-as-mutation-boundary.md)
- [ADR-0003: Plugin and document-schema versions are independent](0003-independent-plugin-and-schema-versioning.md)
- [ADR-0004: Source sessions use conflict-safe single-writer ownership](0004-conflict-safe-source-sessions.md)
- [ADR-0005: Interaction is popup-first and registry-driven](0005-popup-first-registry-driven-interaction.md)

These first records document decisions that predate the ADR process. Their
dates therefore record adoption into the decision log, not the first commit
that implemented the behavior.

← [Documentation home](../README.md) | [Architecture](../development/architecture.md)
