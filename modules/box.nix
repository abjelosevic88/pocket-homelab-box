# The Pocket Box: Pocket Core plus the Pocket apps, each as one hardened systemd service with its
# data in /var/lib/pocket-<slug>, listening on loopback behind Caddy (modules/proxy.nix), which serves
# every app at https://<slug>.<domain>. Apps register with Core on start using a registration key that
# is generated on the first boot, so no secret is ever baked into an image.
{ config, lib, pkgs, ... }:

let
  cfg = config.pocket.box;
  catalog = import ../apps.nix { inherit lib; };
  enabled = lib.filterAttrs (slug: _: slug == "core" || lib.elem slug cfg.apps) catalog;
  apps = lib.filterAttrs (slug: _: slug != "core") enabled;

  url = import ./urls.nix cfg;
  publicUrl = slug: url.site slug;
  localUrl = app: "http://127.0.0.1:${toString app.port}";
  secretsFile = "/var/lib/pocket-box/secrets.env";
  # Install and Remove (modules/installer.py): an app runs only while its marker exists.
  appMarkers = "/var/lib/pocket-box/apps";
  installerEnv = "/var/lib/pocket-box/installer.env";
  installerSocket = "/run/pocket-box-installer/installer.sock";
  installerConfig = pkgs.writeText "pocket-box-installer.json" (builtins.toJSON {
    socket = installerSocket;
    markers = appMarkers;
    data_root = "/var/lib";
    token_file = installerEnv;
    name_file = "/var/lib/pocket-box-name/domain";
    inherit (cfg) domain;
    platform = pkgs.stdenv.hostPlatform.system;
    catalog_url = "https://github.com/abjelosevic88/pocket-homelab-core/releases/download/catalog/apps.json";
    tools.systemctl = "${pkgs.systemd}/bin/systemctl";
    apps = lib.mapAttrs (_: app: { inherit (app) title version port; }) apps;
  });
  screenConfig = pkgs.writeText "pocket-box-screen.json" (builtins.toJSON {
    out = "/run/pocket-box-screen/screen.issue";
    name_file = "/var/lib/pocket-box-name/domain";
    choice_file = "/var/lib/pocket-box-name/choice.json";
    password_flag = "/var/lib/pocket-box/agent/password-set";
    inherit (url) landing;
    qrencode = "${pkgs.qrencode}/bin/qrencode";
    agetty = "${pkgs.util-linux}/bin/agetty";
  });
  screen = pkgs.writers.writePython3 "pocket-box-screen" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./screen.py);
  installer = pkgs.writers.writePython3 "pocket-box-installer" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./installer.py);

  mediaDir = "/srv/media";

  # In front of every app: once the box has its public name (modules/names.nix), the app's public URLs
  # use it instead of <domain>. Without the name it changes nothing.
  envWrap = pkgs.writeShellScript "pocket-box-env" ''
    name=$(cat /var/lib/pocket-box-name/domain 2>/dev/null || true)
    if [ -n "$name" ]; then
      # env -0, not compgen: the system's bash is built without programmable completion.
      while IFS= read -r -d "" kv; do
        k=''${kv%%=*}
        v=''${kv#*=}
        case "$v" in
          *.${cfg.domain}*|*//${cfg.domain}*)
            v=''${v//.${cfg.domain}/.$name}
            v=''${v//\/\/${cfg.domain}/\/\/$name}
            export "$k=$v" ;;
        esac
      done < <(env -0)
    fi
    exec "$@"
  '';

  common = slug: app:
    let
      root = app.root or false;
      caps = app.capabilities or [ ];
      media = app.media or null;
    in
    {
      description = app.title;
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "pocket-box-secrets.service" "pocket-box-ca.service" "pocket-box-apps.service" ];
      wants = [ "network-online.target" "pocket-box-ca.service" "pocket-box-apps.service" ];
      # Installed (Core → Apps → Install an app) or not: see modules/installer.py. Core always runs.
      unitConfig = lib.optionalAttrs (slug != "core") { ConditionPathExists = "${appMarkers}/${slug}"; };
      requires = [ "pocket-box-secrets.service" ];
      environment = {
        DATA_DIR = "/var/lib/pocket-${slug}";
        HOME = "/var/lib/pocket-${slug}";
        HOST = "127.0.0.1";
        PORT = toString app.port;
        BASE_URL = publicUrl slug;
        SECURE_COOKIES = "true";
        # The system CAs plus the box's own, so apps can reach each other (and Core's OIDC) over https.
        SSL_CERT_FILE = url.caBundle;
        LOG_LEVEL = "info";
      } // lib.optionalAttrs (config.time.timeZone != null) {
        # Otherwise the apps follow /etc/localtime, which the setup wizard sets.
        TZ = config.time.timeZone;
      } // (app.environment or { });
      serviceConfig = {
        ExecStart = "${envWrap} ${lib.getExe pkgs.pocket.${slug}}";
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
  imports = [ ./services.nix ./proxy.nix ./system.nix ./updates.nix ./names.nix ];

  options.pocket.box = {
    enable = lib.mkEnableOption "the Pocket Box (Pocket Core and the Pocket apps)";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}.local";
      defaultText = lib.literalExpression ''"''${config.networking.hostName}.local"'';
      description = ''
        The box's own name. Every app is served at https://<slug>.<domain>, the bare domain is the
        landing page. Names under .local are announced over mDNS.
      '';
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Port Caddy serves https on. Anything but 443 ends up in every URL.";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Port of the plain-http landing page (certificate download) and the https redirects.";
    };

    apps = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames catalog));
      default = lib.attrNames catalog;
      description = "Which Pocket apps run on the box. Core always runs.";
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
            # Core's key to the app installer (only Core reads this file; the apps never see it).
            i=${installerEnv}
            if [ ! -s "$i" ]; then
              printf 'INSTALLER_TOKEN=pinst_%s\n' "$(head -c 24 /dev/urandom | base32 | tr -d '=' | tr 'A-Z' 'a-z')" > "$i.tmp"
              mv "$i.tmp" "$i"
            fi
          '';
        };

        pocket-core.environment.OIDC_ISSUER = publicUrl "core";

        # Which apps are installed. On the first boot (a new box, or one updating to the release that
        # brought Install and Remove) every app the box carries is; apps that arrive later with an
        # update start out not installed, ready in Core → Apps → Install an app.
        pocket-box-apps = {
          description = "Pocket Box installed apps";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = { Type = "oneshot"; RemainAfterExit = true; StateDirectory = "pocket-box"; StateDirectoryMode = "0700"; };
          path = [ pkgs.coreutils ];
          script = ''
            d=${appMarkers}
            if [ ! -e "$d/.seeded" ]; then
              mkdir -p "$d"
              for a in ${lib.concatStringsSep " " (lib.attrNames apps)}; do touch "$d/$a"; done
              touch "$d/.seeded"
            fi
          '';
        };

        pocket-box-screen = {
          description = "Pocket Box screen (address and console login)";
          wantedBy = [ "multi-user.target" ];
          before = [ "getty@tty1.service" "serial-getty@ttyS0.service" ];
          serviceConfig = { Type = "oneshot"; ExecStart = "${screen} ${screenConfig}"; RuntimeDirectory = "pocket-box-screen"; RuntimeDirectoryPreserve = "yes"; };
        };

        pocket-box-installer = {
          description = "Pocket Box app installer (Install and Remove for Pocket Core)";
          wantedBy = [ "multi-user.target" ];
          after = [ "pocket-box-secrets.service" "pocket-box-apps.service" ];
          requires = [ "pocket-box-secrets.service" ];
          wants = [ "pocket-box-apps.service" ];
          before = [ "pocket-core.service" ];
          serviceConfig = {
            ExecStart = "${installer} ${installerConfig}";
            RuntimeDirectory = "pocket-box-installer";
            RuntimeDirectoryMode = "0750";
            Group = "pocket-box-agent";
            UMask = "0007";
            Restart = "on-failure";
            RestartSec = 3;
          };
        };

        pocket-core = {
          wants = [ "pocket-box-installer.service" ];
          after = [ "pocket-box-installer.service" ];
          environment.INSTALLER_SOCKET = installerSocket;
          serviceConfig.EnvironmentFile = [ installerEnv ];
        };
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

    # Shared media (films, series, music, books, audiobooks, games) for the apps and services that use it.
    users.groups.pocket-media = { };
    systemd.tmpfiles.settings."10-pocket-media" = lib.genAttrs
      ([ mediaDir ] ++ map (d: "${mediaDir}/${d}") [ "movies" "tv" "music" "books" "audiobooks" "games" ])
      (_: { d = { mode = "2775"; user = "root"; group = "pocket-media"; }; });

    # pocket.local on the LAN (the per-app names are announced by modules/proxy.nix).
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      settings.publish = {
        # nixpkgs turns all publishing off unless this is set explicitly.
        disable-publishing = false;
        publish-addresses = true;
        publish-workstation = true;
      };
    };

    # Caddy serves every app; the apps themselves only listen on loopback.
    pocket.box.sites = lib.mapAttrs (_: app: app.port) enabled;

    # The box's screen: the address (with a QR code) and how the console login works, kept current by
    # pocket-box-screen (modules/screen.py). The help line is what shows if that ever fails.
    services.getty.helpLine = ''

      Pocket Box: open ${url.landing} on a phone or laptop on the same network.
    '';
    environment.etc."issue.d/pocket-box.issue".source = "/run/pocket-box-screen/screen.issue";
    # Again when the box gets its name or a console password, and every few minutes besides.
    systemd.paths.pocket-box-screen = {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = [ "/var/lib/pocket-box-name/domain" "/var/lib/pocket-box-name/choice.json" "/var/lib/pocket-box/agent/password-set" ];
        Unit = "pocket-box-screen.service";
      };
    };
    systemd.timers.pocket-box-screen = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnBootSec = "1min"; OnUnitActiveSec = "5min"; };
    };
  };
}
