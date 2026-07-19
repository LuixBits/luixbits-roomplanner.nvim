# Releasing

The authoritative checklist is [`RELEASE.md`](../../RELEASE.md). Releases are
evidence-based: do not tag around a failing required check, and keep plugin
versioning separate from persisted schema versioning.

## Prepare

1. Create a focused release branch or pull request and choose a SemVer plugin
   version.
2. Move curated `Unreleased` notes to a dated release section, restore an empty
   `Unreleased` section, and verify `./scripts/release-notes.sh vX.Y.Z`.
3. Review the [compatibility policy](compatibility.md), schema
   migrations/fixtures, `LICENSE`, `NOTICE`, security/support routes, roadmap,
   and offline help.
4. Run the complete automated gate:

   ```sh
   ./scripts/release-check.sh
   ```

5. Review benchmark changes rather than treating machine-dependent time as a
   hard threshold.

## Compatibility smoke

Confirm required CI for the selected Neovim 0.10 and 0.11 patches, 0.12.4, and
the Linux/macOS/Windows smoke matrix. Nightly is visible but non-blocking.

Manually exercise a keyboard-only plan at compact, medium, and wide terminal
sizes; Unicode and ASCII; light and dark colorschemes; vanilla `vim.ui` and one
enhanced provider. Test a clean install through native/`vim.pack`, lazy.nvim,
Nix/nvf, and rocks-git while no tagged LuaRock is published. Run
`:checkhealth roomplan` with no session, standalone JSON, and Norg.

## Publish and verify

- Ensure release-commit CI is green, the worktree contains only intended
  release files, and help tags are current.
- Confirm private vulnerability reporting and conservative main/tag repository
  rules are enabled.
- Merge, then create and push a signed tag, or an annotated tag when signing is
  unavailable. Never use a lightweight release tag.
- Wait for the required tag-triggered CI matrix, then manually dispatch the
  GitHub **Release** workflow with the exact tag. It revalidates the tag and
  changelog, reruns the release gate, and creates the release without
  overwriting an existing one.
- Test both default-branch and pinned-tag installation after publication.
- Publish a LuaRock only from the tested tagged source, then update the install
  chapter away from the rocks-git fallback.

If a published source or schema problem is discovered, document recovery
before convenience. Never rewrite or reuse a pushed tag, and never silently
reinterpret existing plan data. Fix source problems with a new version; rerun
publication for an unchanged tag only when its release was never created.

← [Contributing](contributing.md) | [Documentation home](../README.md) | [Roadmap](../reference/limitations-and-roadmap.md) →
