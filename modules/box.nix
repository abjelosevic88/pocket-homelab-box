# The Pocket Box: Pocket Core plus the Pocket apps, each as one hardened systemd service with its
# data in /var/lib/pocket-<slug>. Apps register with Core on start using a registration key that is
# generated on the first boot, so no secret is ever baked into an image.
{ config, lib, pkgs, ... }:

let
  cfg = config.pocket.box;
  catalog = import ../apps.nix { inherit lib; };
  enabled = lib.filterAttrs (slug: _: slug == "core" || lib.elem slug cfg.apps) catalog;
  apps = lib.filterAttrs (slug: _: slug != "core") enabled;

  publicUrl = app: "${cfg.scheme}://${cfg.host}:${toString app.port}";
  localUrl = app: "http://127.0.0.1:${toString app.port}";
  secretsFile = "/var/lib/pocket-box/secrets.env";

  mediaDir = "/srv/media";

  common = slug: app:
    let
      root = app.root or false;
      caps = app.capabilities or [ ];
      media = app.media or null;
    in
    {
      description = app.title;
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "pocket-box-secrets.service" ];
      wants = [ "network-online.target" ];
      requires = [ "pocket-box-secrets.service" ];
      environment = {
        DATA_DIR = "/var/lib/pocket-${slug}";
        HOME = "/var/lib/pocket-${slug}";
        HOST = cfg.listen;
        PORT = toString app.port;
        BASE_URL = publicUrl app;
        SECURE_COOKIES = lib.boolToString (cfg.scheme == "https");
        TZ = if config.time.timeZone != null then config.time.timeZone else "UTC";
        LOG_LEVEL = "info";
      } // (app.environment or { });
      serviceConfig = {
        ExecStart = lib.getExe pkgs.pocket.${slug};
        EnvironmentFile = [ secretsFile ];
        DynamicUser = !root;
        StateDirectory = "pocket-${slug}";
        StateDirectoryMode = "0750";
        WorkingDirectory = "/var/lib/pocket-${slug}";
        Restart = "on-failure";
        RestartSec = 3;
        NoNewPrivileges = true;
        # Apps that run as root (Backups, Database) need the disks and the other apps' data.
        ProtectSystem = if root then "full" else "strict";
        ProtectHome = !root;
        PrivateDevices = !root;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ]
          ++ lib.optional (lib.elem "CAP_NET_RAW" caps) "AF_PACKET";
      } // lib.optionalAttrs (caps != [ ]) {
        AmbientCapabilities = caps;
        CapabilityBoundingSet = caps;
      } // lib.optionalAttrs (media != null) {
        SupplementaryGroups = [ "pocket-media" ];
        UMask = "0002";
      } // lib.optionalAttrs (media == "rw") {
        ReadWritePaths = [ mediaDir ];
      };
    };
in
{
  imports = [ ./services.nix ];

  options.pocket.box = {
    enable = lib.mkEnableOption "the Pocket Box (Pocket Core and the Pocket apps)";

    host = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}.local";
      defaultText = lib.literalExpression ''"''${config.networking.hostName}.local"'';
      description = "Name people use to reach the box. Ends up in every app's BASE_URL and in Core's OIDC issuer.";
    };

    scheme = lib.mkOption {
      type = lib.types.enum [ "http" "https" ];
      default = "http";
      description = "Scheme of the public URLs. https turns on secure cookies (needs a TLS front, not set up yet).";
    };

    listen = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address the apps listen on.";
    };

    apps = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames catalog));
      default = lib.attrNames catalog;
      description = "Which Pocket apps run on the box. Core always runs.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the app ports on the LAN.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mkMerge [
      {
        # One registration key per box, made on the first boot and shared by Core and the apps.
        pocket-box-secrets = {
          description = "Pocket Box first-boot secrets";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StateDirectory = "pocket-box";
            StateDirectoryMode = "0700";
            UMask = "0077";
          };
          path = [ pkgs.coreutils ];
          script = ''
            f=${secretsFile}
            if [ ! -s "$f" ]; then
              key="pcreg_$(head -c 24 /dev/urandom | base32 | tr -d '=' | tr 'A-Z' 'a-z')"
              printf 'REGISTRATION_KEY=%s\nCORE_REGISTRATION_KEY=%s\n' "$key" "$key" > "$f.tmp"
              mv "$f.tmp" "$f"
            fi
          '';
        };

        pocket-core.environment.OIDC_ISSUER = publicUrl catalog.core;
      }

      (lib.mapAttrs' (slug: app: lib.nameValuePair "pocket-${slug}" (common slug app)) enabled)

      (lib.mapAttrs' (slug: app: lib.nameValuePair "pocket-${slug}" {
        after = [ "pocket-core.service" ];
        wants = [ "pocket-core.service" ];
        environment = {
          CORE_URL = localUrl catalog.core;
          CORE_APP_URL = localUrl app;
        };
      }) apps)
    ];

    # Shared media (films, series, music, books, audiobooks) for the apps and services that use it.
    users.groups.pocket-media = { };
    systemd.tmpfiles.settings."10-pocket-media" = lib.genAttrs
      ([ mediaDir ] ++ map (d: "${mediaDir}/${d}") [ "movies" "tv" "music" "books" "audiobooks" ])
      (_: { d = { mode = "2775"; user = "root"; group = "pocket-media"; }; });

    # pocket.local on the LAN, and the box can resolve its own name (apps fetch Core's OIDC discovery).
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      settings.publish = {
        publish-addresses = true;
        publish-workstation = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall
      (lib.mapAttrsToList (_: app: app.port) enabled);

    services.getty.helpLine = ''

      Pocket Box: open ${publicUrl catalog.core} to set it up.
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (_: app: "  ${app.title}: ${publicUrl app}") apps)}
    '';
  };
}
