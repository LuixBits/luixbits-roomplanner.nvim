# Installation

[← Documentation home](../README.md) · [Next: Quick start →](quick-start.md)

RoomPlan requires Neovim 0.10 or newer and has no mandatory runtime
dependencies. Neorg support is optional.

## lazy.nvim

```lua
{
  "LuixBits/luixbits-roomplanner.nvim",
  lazy = false,
  main = "roomplan",
  opts = {},
}
```

Keeping RoomPlan non-lazy is the least surprising setup because commands such
as `:RoomPlanInit path` and `:RoomPlanOpen path` must work from arbitrary
buffers. Command-based lazy loading is possible, but every RoomPlan command
must be included in the plugin specification.

## Neovim 0.12 `vim.pack`

```lua
vim.pack.add({
  { src = "https://github.com/LuixBits/luixbits-roomplanner.nvim" },
})

require("roomplan").setup({})
```

`vim.pack` is available in Neovim 0.12 and newer.

## Nix flake

Add RoomPlan to the inputs of your configuration:

```nix
inputs.roomplan = {
  url = "github:LuixBits/luixbits-roomplanner.nvim";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

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

Until RoomPlan publishes a tagged LuaRock, use `rocks-git.nvim`:

```vim
:Rocks install rocks-git.nvim
:Rocks install LuixBits/luixbits-roomplanner.nvim
```

Or declare the Git source in `rocks.toml`:

```toml
[plugins."luixbits-roomplanner.nvim"]
git = "LuixBits/luixbits-roomplanner.nvim"
```

## Native packages or another manager

Any package manager that adds the repository root to `runtimepath` works. A
native start-package installation needs only Git:

```sh
git clone https://github.com/LuixBits/luixbits-roomplanner.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/roomplan.nvim
nvim --headless "+helptags ALL" +qa
```

For a local development checkout:

```lua
vim.opt.runtimepath:prepend("/absolute/path/to/luixbits-roomplanner.nvim")
require("roomplan").setup({})
```

The runtime plugin registers commands automatically. Calling `setup()` is
optional when the defaults are sufficient and safe to repeat when configuring
options.

## Snacks and other UI providers

RoomPlan owns its workspace, forms, and action windows. Scalar editors and
confirmation prompts use standard `vim.ui.input` and `vim.ui.select`, so
Snacks, dressing.nvim, or another `vim.ui` provider can enhance those prompts
without a RoomPlan-specific adapter.

[← Documentation home](../README.md) · [Next: Quick start →](quick-start.md)
