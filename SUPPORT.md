# Support

RoomPlan is maintained as an open-source project on a best-effort basis.

## Before opening an issue

1. Read the [installation guide](docs/getting-started/installation.md) and
   [troubleshooting guide](docs/reference/troubleshooting.md).
2. Run `:checkhealth roomplan` and review every warning.
3. Reproduce with the latest tagged release. If no release exists yet, use the
   current `main` branch.
4. Try the repository's `scripts/minimal_init.lua` when the problem may be
   caused by plugin-manager ordering or another plugin.
5. Search existing issues before creating a new one.

Bug reports should include the Neovim version, RoomPlan tag or commit, operating
system, installation method, relevant configuration, `:checkhealth roomplan`
output, exact reproduction steps, and the complete error. Remove private paths
or plan contents before posting.

Questions and reproducible bugs may use
[GitHub Issues](https://github.com/LuixBits/luixbits-roomplanner.nvim/issues).
Feature requests should describe the planning workflow and user problem before
proposing UI, mappings, configuration, or schema fields.

Do not report vulnerabilities or sensitive data in a public issue. Follow
[SECURITY.md](SECURITY.md) instead.
