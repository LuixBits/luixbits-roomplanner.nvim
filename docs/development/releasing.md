# Releasing

The authoritative checklist is [`RELEASE.md`](../../RELEASE.md). Releases are
evidence-based: do not tag around a failing required check, and keep plugin
versioning separate from persisted schema versioning.

## Prepare

1. Choose a SemVer plugin version and move completed `Unreleased` notes in
   `CHANGELOG.md`.
2. Review schema compatibility, migrations/fixtures, `LICENSE`, and `NOTICE`.
3. Run the complete automated gate:

   ```sh
   ./scripts/release-check.sh
   ```

4. Review benchmark changes rather than treating machine-dependent time as a
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

- Ensure the worktree contains only intended release files and help tags are
  current.
- Create and push the signed/annotated tag and GitHub release notes.
- Test both default-branch and pinned-tag installation after publication.
- Publish a LuaRock only from the tested tagged source, then update the install
  chapter away from the rocks-git fallback.
- Restore an `Unreleased` changelog section immediately.

If a published source or schema problem is discovered, document recovery
before convenience. Never rewrite a tag or silently reinterpret existing plan
data.

← [Contributing](contributing.md) | [Documentation home](../README.md)
