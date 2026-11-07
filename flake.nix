{
  description = "Nix garbage collection with more control";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      version = builtins.head (builtins.match ".*\nversion: *([0-9.]+).*" (builtins.readFile ./shard.yml));
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = import ./package.nix {
            inherit pkgs version;
            src = self;
          };
        }
      );

      nixosModules =
      rec {
        nixos-safe-gc = {pkgs,...}@args: import ./module.nix self.packages.${pkgs.stdenv.hostPlatform.system}.default args;
        default = nixos-safe-gc;
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              crystal
              crystal2nix
              shards
              ameba-ls
              crystalline
              bashInteractive # https://discourse.nixos.org/t/interactive-bash-with-nix-develop-flake/15486
              nixd
              nil
            ];
            shellHook = ''
              ln -sf ${pkgs.ameba-ls}/bin/ameba-ls $HOME/.local/bin/ameba-ls
              ln -sf ${pkgs.crystalline}/bin/crystalline $HOME/.local/bin/crystalline
            '';
          };
        }
      );
    };
}
