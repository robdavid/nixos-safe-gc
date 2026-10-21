{ pkgs
, src
, version ? "0.0.1"
}:

pkgs.crystal.buildCrystalPackage {
  pname = "nixos-safe-gc";
  inherit version;

  src = pkgs.lib.cleanSourceWith {
    inherit src;
    filter =
      path: type:
      let
        baseName = pkgs.lib.baseNameOf (toString path);
      in
      !(builtins.elem baseName [
        ".direnv"
        ".git"
        "bin"
        "result"
      ]);
  };

  shardsFile = ./shards.nix;
  format = "shards";
  doCheck = false;
  doInstallCheck = false;
  buildInputs = with pkgs; [
    openssl
    pkg-config
    pcre
    ameba
    gmp
  ];
}
