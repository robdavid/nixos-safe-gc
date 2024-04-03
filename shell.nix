{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    crystal
    crystalline
    shards
    crystal2nix
    openssl
    pkg-config
    pcre
    ameba
  ];
  shellHook = "ln -snf ${pkgs.crystalline.outPath} ~/.local/crystalline";
}
