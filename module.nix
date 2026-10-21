{ config
, lib
, pkgs
, utils
, ...
}:

let
  cfg = config.services.nixos-safe-gc;

  # The three retention constraints understood by nixos-safe-gc:
  #   --generations N    keep at least the N most recent generations
  #   --days N           keep at least N days worth of generations
  #   --keep-kernel [V]  keep a generation running kernel V; without an
  #                      argument the currently running kernel is used
  kernelArgs =
    if cfg.kernel == null then
      [ ]
    else if cfg.kernel == "" then
      [ "--keep-kernel" ]
    else
      [ "--keep-kernel" cfg.kernel ];

  gcArgs = [
    "--generations"
    (toString cfg.generations)
    "--days"
    (toString cfg.days)
  ]
  ++ kernelArgs
  ++ lib.optional cfg.dryRun "--dry-run";

  userArgs = lib.concatMap (user: [ "--user" user ]) cfg.users;

  args = gcArgs ++ userArgs;

  exe = "${cfg.package}/bin/nixos-safe-gc";
in
{
  options.services.nixos-safe-gc = {
    enable = lib.mkEnableOption "the nixos-safe-gc NixOS garbage collector";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { src = ./.; };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { src = ./.; }";
      description = ''
        The nixos-safe-gc package to use. The default builds the tool from
        the sources of this flake using the Nixpkgs of the system
        configuration.
      '';
    };

    time = lib.mkOption {
      type = lib.types.str;
      default = "04:00";
      example = "03:30";
      description = ''
        Time of day at which the garbage collection is started, in the
        `HH:MM` format and in the local timezone of the system. The
        collection runs every day at that time.
      '';
    };

    randomDelay = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "1h";
      example = "30min";
      description = ''
        Maximum random delay added to the start time of the garbage
        collection, to avoid all systems in a fleet collecting garbage at
        exactly the same time. Set to `null` to disable the random delay.
      '';
    };

    kernel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "6.6.20";
      description = ''
        Kernel version that at least one of the retained generations has to
        use. The following values are possible:

        * `null` (the default): no kernel constraint is applied; the
          generations are only constrained by {option}`generations` and
          {option}`days`.
        * `""`: the generation running the currently booted kernel is
          retained.
        * `"<version>"`: the most recent generation using that kernel version
          is retained.
      '';
    };

    generations = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = ''
        Minimum number of the most recent generations that are retained.

        The constraint only decides which generations are kept in the system
        profile, and thus which store paths stay reachable. The store garbage
        collection itself removes all unreachable paths, independently of this
        setting.
      '';
    };

    days = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 7;
      description = ''
        Minimum number of days the retained generations have to span. The
        garbage collector never deletes anything that is younger than this.
        Note that the underlying `nix-collect-garbage --delete-older-than`
        option has a granularity of one day and never deletes anything that
        is younger than a day.

        Like {option}`generations`, this only constrains which generations are
        kept in the system profile; the store garbage collection removes all
        unreachable paths regardless of their age.
      '';
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" "bob" ];
      description = ''
        Users the garbage collection is run for. The garbage collector is
        then run as each of these users, so that only their own profiles are
        affected. If the list is empty, the garbage collection is run as
        `root`, which affects the profiles of all users of the system.

        Note that the retention policy is always derived from the
        generations of the system profile, also when the garbage collection
        is run for other users.
      '';
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Only show what would be collected, without actually collecting
        anything.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.match "[0-9]{2}:[0-9]{2}" cfg.time != null;
        message = ''
          services.nixos-safe-gc.time has to be given in the `HH:MM` format.
        '';
      }
      {
        assertion = cfg.users == [ ] || config.security.sudo.enable;
        message = ''
          services.nixos-safe-gc.users requires security.sudo to be enabled,
          because the garbage collection is run as another user via sudo.
        '';
      }
      {
        assertion = cfg.kernel == null || cfg.kernel == "" || builtins.match "[A-Za-z0-9._+-]+" cfg.kernel != null;
        message = ''
          services.nixos-safe-gc.kernel must be a plain kernel version, it
          may only contain letters, digits and the characters '.', '_', '+'
          and '-'.
        '';
      }
      {
        assertion = lib.all (user: builtins.match "[A-Za-z0-9._-]+" user != null) cfg.users;
        message = ''
          The users listed in services.nixos-safe-gc.users may only contain
          letters, digits and the characters '.', '_' and '-'.
        '';
      }
    ];

    systemd.services.nixos-safe-gc = {
      description = "NixOS safe garbage collection";
      wantedBy = [ "multi-user.target" ];
      after = lib.optionals config.nix.enable [ "nix-daemon.socket" ];
      wants = lib.optionals config.nix.enable [ "nix-daemon.socket" ];
      path = [
        config.nix.package
        config.system.build.nixos-rebuild
        pkgs.coreutils
      ]
      ++ lib.optional (cfg.users != [ ]) pkgs.sudo;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = utils.escapeSystemdExecArgs ([ exe ] ++ args);
      };
    };

    systemd.timers.nixos-safe-gc = {
      description = "Timer for the NixOS safe garbage collection";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${cfg.time}:00";
        Persistent = true;
      }
      // lib.optionalAttrs (cfg.randomDelay != null) {
        RandomizedDelaySec = cfg.randomDelay;
      };
    };

    # sudo resets the environment of the command it runs, which would leave
    # the garbage collector without nixos-rebuild and nix-collect-garbage in
    # its PATH.
    security.sudo.extraConfig = lib.mkIf (cfg.users != [ ]) ''
      Defaults env_keep += "PATH"
    '';
  };
}
