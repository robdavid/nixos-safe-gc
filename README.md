# nixos-safe-gc

A small [Crystal](https://crystal-lang.org) command line tool that runs a
NixOS garbage collection while making sure that the generations you care about
survive it.

The tool looks at the generations of the system profile, works out the oldest
generation that has to be kept, and then calls

```
nix-collect-garbage --delete-older-than <N>d
```

with a cut-off that is old enough to keep that generation (and everything
newer than it) around.

Because the cut-off is derived from the actual generations of the system, the
collection never removes the running system, a kernel you still need, or the
generations you explicitly asked to keep.

The flake also ships a NixOS module that installs the tool and runs it on a
schedule.

## NixOS module

### Usage

Add the flake to the inputs of your configuration and import the module:

```nix
{
  inputs.nixos-safe-gc.url = "github:<owner>/nixos-safe-gc";

  # ...

  outputs = { nixpkgs, nixos-safe-gc, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-safe-gc.nixosModules.nixos-safe-gc
        ./configuration.nix
      ];
    };
  };
}
```

Then enable it in your host configuration:

```nix
{
  services.nixos-safe-gc = {
    enable = true;

    time = "04:00";
    kernel = "";
    generations = 3;
    days = 14;
  };
}
```

This installs the `nixos-safe-gc.service` unit and a matching
`nixos-safe-gc.timer` that starts the collection every day at 04:00 (local
time of the system). The timer is persistent, so a collection that was missed
while the machine was off is run after the next boot.

### Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `services.nixos-safe-gc.enable` | bool | `false` | Enable the collector and its timer. |
| `services.nixos-safe-gc.package` | package | built from this flake | The `nixos-safe-gc` package to use. The default builds the tool with the Nixpkgs of the system configuration. |
| `services.nixos-safe-gc.time` | string | `"04:00"` | Time of day the collection starts, in `HH:MM` format, in the local timezone. |
| `services.nixos-safe-gc.randomDelay` | string or `null` | `"1h"` | Maximum random delay added to the start time, so that a fleet of machines does not collect garbage at exactly the same time. Set to `null` to disable it. |
| `services.nixos-safe-gc.kernel` | string or `null` | `null` | Kernel version that one of the retained generations has to use, see below. |
| `services.nixos-safe-gc.generations` | positive int | `1` | Minimum number of the most recent generations that are retained. |
| `services.nixos-safe-gc.days` | int | `7` | Minimum number of days the retained generations have to span. |
| `services.nixos-safe-gc.users` | list of strings | `[]` | Users the collection is run for. If the list is empty, the collection runs as `root` and affects the profiles of all users. |
| `services.nixos-safe-gc.dryRun` | bool | `false` | Only show what would be collected, without collecting anything. |

### The kernel constraint

`kernel` mirrors the tri-state of the `--keep-kernel` option of the command
line tool:

- `null` (the default): no kernel constraint, the generations are only
  constrained by `generations` and `days`.
- `""`: the generation running the currently booted kernel is retained.
- `"6.6.20"`: the most recent generation using that kernel version is
  retained.

### How the cut-off is calculated

The tool keeps the oldest of the following generations:

1. the `generations`-th most recent generation,
2. the most recent generation running the requested kernel, if any,

and additionally never uses a cut-off that is younger than `days`. The age of
that generation (or `days`, whichever is larger) is rounded up to whole days
and used as the cut-off of `nix-collect-garbage --delete-older-than`.
`nix-collect-garbage` keeps every generation that is newer than the cut-off
plus the first one that is older, so the result is always slightly more
conservative than requested.

A few things worth knowing:

- The constraints only decide which generations stay in the system profile,
  and therefore which store paths remain reachable. The store garbage
  collection itself removes *all* unreachable paths, independently of their
  age.
- `--delete-older-than` has a granularity of one day, so nothing that is
  younger than a day is ever deleted.
- If the system has fewer generations than `generations` requires, all of
  them are kept and the collection still runs.
- A kernel that is not used by any generation is reported as a warning; the
  remaining constraints are still applied.

### Collecting garbage for other users

With `users` set, the collection is run as each of those users, so that only
their own profiles are affected:

```nix
{
  services.nixos-safe-gc = {
    enable = true;
    users = [ "alice" "bob" ];
  };

  security.sudo.enable = true;
}
```

This requires `security.sudo.enable` to be set, the module fails the
evaluation otherwise. The tool re-executes itself with `sudo -u <user>`; since
it runs as `root` in the first place, `sudo` does not ask for a password. The
module additionally adds `Defaults env_keep += "PATH"` to the sudo
configuration, so that the re-executed process still finds `nixos-rebuild`
and `nix-collect-garbage`.

Note that the retention policy is always derived from the generations of the
*system* profile, even when the collection is run for other users.

## Command line usage

The tool can also be used without the module:

```
Usage: nixos-safe-gc [options]
    -k [VERSION], --keep-kernel [VERSION]
                                     Keep generation with the given kernel version (defaults to current kernel)
    -d DAYS, --days DAYS             Keep at least the given number of days worth of generations
    -g GENERATIONS, --generations GENERATIONS
                                     Keep at least the given number of generations
    -R, --dry-run                    Don't perform a GC, but show what would be done
    -u USER, --user USER             One or more users to run the garbage collection for
    -h, --help                       Show this help
```

The generations are read with `nixos-rebuild list-generations --json`, so the
tool has to run on a NixOS system.

## Development

```console
$ nix develop          # Crystal toolchain, shards, ameba, crystalline
$ nix build            # build the package
$ nix flake check      # evaluate the flake outputs and the NixOS module
```

The sources of the tool are in `main.cr`, the package definition in
`package.nix` and the NixOS module in `module.nix`.
