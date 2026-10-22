{
  description = "apple-pinyin-ascii-punctuation: ASCII punctuation for Apple Simplified Pinyin on macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      forDarwin =
        f:
        nixpkgs.lib.genAttrs [
          "aarch64-darwin"
          "x86_64-darwin"
        ] (system: f (import nixpkgs { inherit system; }));
    in
    {
      homeManagerModules.default = import ./apple-pinyin-ascii-punctuation.nix;

      packages = forDarwin (pkgs: {
        default =
          (home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              {
                home.username = "pinyin-ascii";
                home.homeDirectory = "/Users/pinyin-ascii";
                home.stateVersion = "26.05";
              }
            ];
          }).config.services.apple-pinyin-ascii-punctuation.package;
        tools = import ./tools { inherit pkgs; };
      });

      checks = forDarwin (pkgs: {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        tools = self.packages.${pkgs.stdenv.hostPlatform.system}.tools;
        module = import ./tests/module.nix {
          inherit pkgs;
          inherit (home-manager.lib) homeManagerConfiguration;
          module = self.homeManagerModules.default;
        };
      });

      formatter = forDarwin (pkgs: pkgs.nixfmt);
    };
}
