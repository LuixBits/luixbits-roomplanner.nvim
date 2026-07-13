# Release checklist

Releases are evidence-based: keep the runtime dependency-free, keep persisted
schema changes separate from plugin versioning, and do not tag around a red
required check.

## Prepare

- Choose the plugin version and update `CHANGELOG.md` from `Unreleased`.
- If `schema_version` changes, add one sequential migration, old/new fixtures,
  JSON Schema updates, and recovery guidance before continuing.
- Review `LICENSE` and `NOTICE`; record any newly adapted third-party code.
- Run the complete local gate:

  ```sh
  ./scripts/release-check.sh
  ```

  The benchmark is informational. Investigate material regressions, but do not
  turn machine-dependent timing into a noisy pass/fail threshold.

## Compatibility

- Confirm required GitHub Actions jobs are green for Neovim 0.10.4, 0.11.7,
  0.12.4 and the stable Linux/macOS/Windows smoke matrix. Nightly is visible
  but non-blocking.
- Complete one keyboard-only plan workflow at roughly 80x24, 110x35, and
  160x50, using both Unicode and ASCII, one light and one dark colorscheme,
  vanilla `vim.ui`, and one enhanced provider such as Snacks.
- Smoke one clean install through `vim.pack` or native packages, lazy.nvim,
  the Nix package/nvf path, and rocks-git.nvim while no LuaRock is published.
- Run `:checkhealth roomplan` with no plan, with a standalone plan, and with a
  Norg plan; review warnings rather than merely checking that it opens.

## Publish

- Ensure the worktree contains only intended release files and generated help
  tags are current.
- Create and push the signed/annotated SemVer tag and GitHub release notes.
- Re-run a default-branch install and a pinned-tag install after publication.
- Publish a LuaRock only from a tested tagged source; then replace the
  rocks-git fallback in the installation docs with the stable rock command.
- Restore an `Unreleased` section in `CHANGELOG.md` for subsequent work.
