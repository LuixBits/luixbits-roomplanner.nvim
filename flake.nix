{
  description = "A text-first room planner for Neovim";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pluginSource = nixpkgs.lib.fileset.toSource {
        root = ./.;
        fileset = nixpkgs.lib.fileset.unions [
          ./lua
          ./plugin
          ./doc
          ./schema
          ./LICENSE
          ./NOTICE
        ];
      };
      mkPlugin = pkgs:
        pkgs.vimUtils.buildVimPlugin {
          pname = "luixbits-roomplanner.nvim";
          version = self.shortRev or "dev";
          src = pluginSource;
          meta = {
            description = "Terminal-native flat planning for Neovim";
            homepage = "https://github.com/LuixBits/luixbits-roomplanner.nvim";
            license = pkgs.lib.licenses.gpl3Only;
          };
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          plugin = mkPlugin pkgs;
        in
        {
          default = plugin;
          luixbits-roomplanner-nvim = plugin;
        }
      );

      overlays.default = final: _prev: {
        luixbits-roomplanner-nvim = mkPlugin final;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          plugin = self.packages.${system}.default;
        in
        {
          inherit plugin;

          smoke = pkgs.runCommand "roomplan-nvim-smoke" { nativeBuildInputs = [ pkgs.neovim ]; } ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            nvim --headless -u NONE -i NONE -n \
              --cmd "set runtimepath^=${plugin}" \
              -c "lua require('roomplan').setup({}); assert(vim.fn.exists(':RoomPlanOpen') == 2)" \
              -c "qa!"
            touch "$out"
          '';

          workflow = pkgs.runCommand "roomplan-workflow-check" { nativeBuildInputs = [ pkgs.actionlint ]; } ''
            actionlint ${./.github/workflows/ci.yml}
            touch "$out"
          '';
        }
      );
    };
}
