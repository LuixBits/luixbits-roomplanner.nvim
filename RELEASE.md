# Release checklist

Releases are evidence-based: keep the runtime dependency-free, keep persisted
schema changes separate from plugin versioning, and do not tag around a red
required check.

## Release change

- Create a focused release branch or pull request from current `main`.
- Choose the SemVer plugin version. Move the curated `Unreleased` entries to a
  dated `## [X.Y.Z] - YYYY-MM-DD` section in `CHANGELOG.md`, restore an empty
  `Unreleased` section above it, and update comparison links.
- Verify release-note extraction before tagging:

  ```sh
  ./scripts/release-notes.sh vX.Y.Z
  ```

- Review the compatibility policy and clearly label deprecations or breaking
  changes. Plugin SemVer does not change the persisted schema version.
- If `schema_version` changes, add one sequential migration, old/new fixtures,
  JSON Schema updates, and recovery guidance before continuing.
- Review `LICENSE` and `NOTICE`; record any newly adapted third-party code.
- Confirm `SECURITY.md`, support links, issue forms, Vim help, generated help
  tags, and the public roadmap are current.
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

## Repository readiness

- Confirm CI on the release commit is green and the worktree contains only
  intended release files.
- Confirm GitHub private vulnerability reporting is enabled.
- Confirm repository rules prevent force-pushing or deleting `main` and
  release tags. Required CI should remain visible for pull requests.
- Confirm repository topics, description, support links, and the real UI
  screenshot or recording are current.

## Tag and publish

- Merge the reviewed release change and update local `main` from its tracked
  upstream.
- Create a signed tag when signing is configured; otherwise create an annotated
  tag. Lightweight release tags are rejected by the publication workflow:

  ```sh
  git tag -s vX.Y.Z -m "RoomPlan vX.Y.Z"
  git push origin vX.Y.Z
  ```

- Wait for every required CI job triggered by the tag. Nightly remains
  informational. Do not move or reuse a pushed release tag to repair a failure;
  fix forward with a new version.
- From GitHub Actions, manually run **Release** with the exact existing tag.
  The guarded workflow verifies annotated-tag identity, extracts the matching
  changelog section, reruns the complete release gate, and creates the GitHub
  release. It refuses to overwrite an existing release.
- Re-run a default-branch install and a pinned-tag install after publication.
- Publish a LuaRock only from a tested tagged source; then replace the
  rocks-git fallback in the installation docs with the stable rock command.

## After publication

- Verify the release page, changelog links, source archives, and installation
  instructions from a clean checkout.
- Open the next milestone and convert accepted roadmap work into focused issues.
- If publication fails after a valid tag, keep the tag immutable, correct the
  workflow or metadata, and rerun publication for that same tag only when no
  release exists.
