# Updates: every night the box moves to the newest release of its own system from the release
# flake (the `stable` branch, which CI moves only after the install test passed), and keeps it only
# if every app comes back healthy (modules/updater.py). Settings → System shows the result and has
# "Check now" and an on/off switch, through the box agent.
{ config, lib, pkgs, ... }:

let
  cfg = config.pocket.box;
  up = cfg.updates;
  catalog = import ../apps.nix { inherit lib; };
  enabled = lib.filterAttrs (slug: _: slug == "core" || lib.elem slug cfg.apps) catalog;
  updaterConfig = pkgs.writeText "pocket-box-update.json" (builtins.toJSON {
    state_dir = "/var/lib/pocket-box/update";
    inherit (up) flake variant;
    health_seconds = 600;
    nix = "${config.nix.package}/bin/nix";
    "nix-env" = "${config.nix.package}/bin/nix-env";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    # The apps on loopback, plus the services they need.
    checks = lib.mapAttrs (_: app: "http://127.0.0.1:${toString app.port}/healthz") enabled;
  });
  updater = pkgs.writers.writePython3 "pocket-box-update" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./updater.py);
in
{
  options.pocket.box = {
    release = {
      version = lib.mkOption { type = lib.types.str; default = "dev"; description = "This release, shown in Settings → System."; };
      rev = lib.mkOption { type = lib.types.str; default = "dev"; description = "Git revision of the release flake."; };
    };

    updates = {
      enable = lib.mkOption { type = lib.types.bool; default = true; description = "Nightly updates with rollback."; };
      flake = lib.mkOption {
        type = lib.types.str;
        default = "github:abjelosevic88/pocket-homelab-box/stable";
        description = "Where releases come from.";
      };
      variant = lib.mkOption {
        type = lib.types.str;
        default = "box";
        description = "This system's name under nixosConfigurations in the release flake.";
      };
      at = lib.mkOption { type = lib.types.str; default = "04:00"; description = "When the nightly update runs (plus up to an hour)."; };
      cache = {
        url = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Binary cache CI fills."; };
        publicKey = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.etc."pocket-box/release.json".text = builtins.toJSON {
        inherit (cfg.release) version rev;
        inherit (up) variant;
      };
      system.nixos.label = "pocket-box-${cfg.release.version}";
    }

    (lib.mkIf (up.cache.url != null && up.cache.publicKey != null) {
      nix.settings.substituters = [ up.cache.url ];
      nix.settings.trusted-public-keys = [ up.cache.publicKey ];
    })

    (lib.mkIf up.enable {
      systemd.services.pocket-box-update = {
        description = "Pocket Box update";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        # The update switches the system; it must not restart or stop itself halfway.
        restartIfChanged = false;
        stopIfChanged = false;
        unitConfig.X-StopOnRemoval = false;
        path = [ config.nix.package pkgs.git ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${updater} ${updaterConfig}";
          StateDirectory = "pocket-box/update";
          TimeoutStartSec = "8h";
        };
      };
      systemd.timers.pocket-box-update = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = up.at;
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
      };
    })
  ]);
}
