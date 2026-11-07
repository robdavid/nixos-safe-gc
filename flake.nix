{
  description = "Nix garbage collection with more controll";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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

      nixosModules = {
        nixos-safe-gc = ./module.nix;
        default = ./module.nix;
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
