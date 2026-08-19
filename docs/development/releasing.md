# Releasing

The root [`RELEASE.md`](../../RELEASE.md) is the authoritative release
checklist. It owns version selection, automated and manual compatibility
checks, tag creation, publication, and post-release verification.

Before preparing a release, also review:

- the [compatibility policy](compatibility.md);
- curated changes in [`CHANGELOG.md`](../../CHANGELOG.md);
- the support and security policy in [`SUPPORT.md`](../../SUPPORT.md) and
  [`SECURITY.md`](../../SECURITY.md);
- current scope in the [public roadmap](../reference/limitations-and-roadmap.md).

Run the complete automated gate from the repository root:

```sh
./scripts/release-check.sh
```

Do not create or move a tag to work around a failed check. Follow the root
checklist for the manual smoke matrix and guarded GitHub release workflow.

← [Contributing](contributing.md) | [Documentation home](../README.md) | [Roadmap](../reference/limitations-and-roadmap.md) →
