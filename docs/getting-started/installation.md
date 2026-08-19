# Installation

[← Documentation home](../README.md) · [Next: Quick start →](quick-start.md)

RoomPlan requires Neovim 0.10 or newer and has no mandatory runtime
dependencies. Neorg support is optional.

The examples below install the newest tagged release. The current exact tag is
`v0.1.0`; use it when you want a reproducible pin. Following `main` gives you
the tested development branch instead.

## lazy.nvim

```lua
{
  "LuixBits/luixbits-roomplanner.nvim",
  version = "*",
  lazy = false,
  main = "roomplan",
  opts = {},
}
```

Set `version = "v0.1.0"` for the exact first release. Omit `version` to follow
`main`.

Keeping RoomPlan non-lazy is the least surprising setup because commands such
as `:RoomPlanInit path` and `:RoomPlanOpen path` must work from arbitrary
buffers. Command-based lazy loading is possible, but every RoomPlan command
must be included in the plugin specification.

## Neovim 0.12 `vim.pack`

```lua
vim.pack.add({
  {
    src = "https://github.com/LuixBits/luixbits-roomplanner.nvim",
    version = vim.version.range("*"),
  },
})

require("roomplan").setup({})
```

Use `version = "v0.1.0"` for an exact tag or omit `version` to follow `main`.
The `vim.pack` lockfile records the resolved revision. `vim.pack` is available
in Neovim 0.12 and newer.

## Nix flake

Add the tagged input to your configuration:

```nix
inputs.roomplan = {
  url = "github:LuixBits/luixbits-roomplanner.nvim/v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The consumer's `flake.lock` records the exact revision. Remove `/v0.1.0` from
the URL only when you intend to follow `main`.

The flake exposes `packages.default`,
`packages.luixbits-roomplanner-nvim`, and `overlays.default` for x86_64 and
aarch64 on Linux and Darwin.

For Home Manager or another module accepting Neovim plugin packages:

```nix
programs.neovim.plugins = [
  inputs.roomplan.packages.${pkgs.stdenv.hostPlatform.system}.default
];
```

For nvf's non-lazy custom-plugin interface:

```nix
vim.extraPlugins.roomplan = {
  package = inputs.roomplan.packages.${pkgs.stdenv.hostPlatform.system}.default;
  setup = "require('roomplan').setup({})";
};
```

Do not call `require("roomplan")` unless the package is also present in the
resulting Neovim runtime. See [Troubleshooting](../reference/troubleshooting.md)
if Nix reports that the Lua module or command is missing.

## rocks.nvim

RoomPlan is not published to LuaRocks yet. Install it through
`rocks-git.nvim`, which follows the newest SemVer tag by default:

```vim
:Rocks install rocks-git.nvim
:Rocks install LuixBits/luixbits-roomplanner.nvim
```

Or declare the Git source in `rocks.toml`:

```toml
[plugins."luixbits-roomplanner.nvim"]
git = "LuixBits/luixbits-roomplanner.nvim"
```

Add `rev = "v0.1.0"` to that table for the exact first release.

## Native packages or another manager

Any package manager that adds the repository root to `runtimepath` works. A
native start-package installation needs only Git:

```sh
git clone --branch v0.1.0 --depth 1 \
  https://github.com/LuixBits/luixbits-roomplanner.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/roomplan.nvim
nvim --headless "+helptags ALL" +qa
```

To work from the development branch instead, clone without `--branch` and
`--depth`, then prepend the checkout in your configuration:

```lua
vim.opt.runtimepath:prepend("/absolute/path/to/luixbits-roomplanner.nvim")
require("roomplan").setup({})
```

The runtime plugin registers commands automatically. Calling `setup()` is
optional when the defaults are sufficient and safe to repeat when configuring
options.

RoomPlan works with Neovim's built-in prompts. See [UI
providers](../configuration/ui-providers.md) if you want Snacks or another
provider to supply floating input and searchable choices.

[← Documentation home](../README.md) · [Next: Quick start →](quick-start.md)
