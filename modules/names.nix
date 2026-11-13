# The box's public name: <random>.box.pockethomelab.net with a Let's Encrypt certificate, so phones
# and laptops open the apps without installing the box's own certificate first. Pocket Names
# (github.com/abjelosevic88/pocket-homelab-names) hands out the name, points it at the box's home
# address and answers Let's Encrypt's DNS check; pocket-box-name (modules/names.py) does the rest on a
# timer. Every box runs the same system, so the name is only known at run time:
#   - Caddy imports the site for it from /var/lib/pocket-box-name/caddy,
#   - pocket-box-env, in front of every Pocket app, swaps <domain> for the public name in the app's
#     environment (BASE_URL, OIDC_ISSUER, …) once /var/lib/pocket-box-name/domain exists,
#   - /etc/hosts is a copy, so the box can add its own public names to it.
# Without internet, or before the first certificate, the box stays on https://<app>.<domain> with its
# own CA, as before. QEMU tests turn it off with -fw_cfg name=opt/pocket/names,string=off.
{ config, lib, pkgs, ... }:

let
  box = config.pocket.box;
  cfg = box.names;
  stateDir = "/var/lib/pocket-box-name";
  appUnits = map (slug: "pocket-${slug}.service") (lib.unique ([ "core" ] ++ box.apps));

  namesConfig = pkgs.writeText "pocket-box-name.json" (builtins.toJSON {
    inherit (cfg) server;
    acme_server = cfg.acmeServer;
    state_dir = stateDir;
    sites = box.sites;
    app_units = appUnits;
    backends_units = [ "pocket-box-backends.service" ];
    caddy_group = config.services.caddy.group;
    tools = {
      lego = "${pkgs.lego}/bin/lego";
      openssl = "${pkgs.openssl}/bin/openssl";
      ip = "${pkgs.iproute2}/bin/ip";
      systemctl = "${pkgs.systemd}/bin/systemctl";
    };
  });
  names = pkgs.writers.writePython3 "pocket-box-name" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./names.py);

  # How the box gets its padlock (modules/address.py): Pocket's address, the owner's own domain on
  # Cloudflare, or the box's own certificate. Core reaches it on the socket, the landing page on the port.
  addressSocket = "/run/pocket-box-address/address.sock";
  addressPort = 7391;
  addressConfig = pkgs.writeText "pocket-box-address.json" (builtins.toJSON {
    socket = addressSocket;
    port = addressPort;
    group = "pocket-box-agent";
    state_dir = stateDir;
    names_server = cfg.server;
    landing = url.landing;
    tools.systemctl = "${pkgs.systemd}/bin/systemctl";
  });
  address = pkgs.writers.writePython3 "pocket-box-address" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./address.py);
  url = import ./urls.nix box;
in
{
  options.pocket.box.names = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Give the box a public name with a Let's Encrypt certificate (needs internet).";
    };
    server = lib.mkOption {
      type = lib.types.str;
      default = "https://names.pockethomelab.com";
      description = "Pocket Names, which hands out the names and answers Let's Encrypt's DNS check.";
    };
    acmeServer = lib.mkOption {
      type = lib.types.str;
      default = "letsencrypt";
      description = "lego's CA: letsencrypt, or letsencrypt-staging for tests.";
    };
  };

  config = lib.mkIf (box.enable && cfg.enable) {
    services.caddy.extraConfig = ''
      import ${stateDir}/caddy/*.caddy
    '';

    # The landing page asks for these to send a browser on to the public name, and to let the owner
    # choose how the box gets it.
    services.caddy.virtualHosts."http://${box.domain}".extraConfig = lib.mkBefore ''
      @name path /name.json /name-status.json
      handle @name {
        header Cache-Control no-store
        root * ${stateDir}/public
        file_server
      }
      handle_path /box-address/* {
        request_body {
          max_size 16KB
        }
        reverse_proxy 127.0.0.1:${toString addressPort}
      }
    '';

    systemd.services.pocket-box-address = {
      description = "Pocket Box address choice (Pocket's address, own domain on Cloudflare, or own certificate)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      before = [ "pocket-core.service" ];
      serviceConfig = {
        ExecStart = "${address} ${addressConfig}";
        RuntimeDirectory = "pocket-box-address";
        RuntimeDirectoryMode = "0750";
        Group = "pocket-box-agent";
        Restart = "on-failure";
        RestartSec = 3;
        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ stateDir ];
      };
    };

    systemd.services.pocket-core = {
      wants = [ "pocket-box-address.service" ];
      after = [ "pocket-box-address.service" ];
      environment.BOX_ADDRESS = addressSocket;
    };

    # So the QEMU switch above is visible early (it is a no-op on real hardware).
    boot.kernelModules = [ "qemu_fw_cfg" ];

    environment.etc.hosts.mode = "0644";
    # Activation writes /etc/hosts afresh; put the public names back.
    system.activationScripts.pocket-box-name-hosts = {
      deps = [ "etc" ];
      text = ''
        if [ -s ${stateDir}/hosts ] && [ ! -L /etc/hosts ]; then
          cat /etc/static/hosts ${stateDir}/hosts > /etc/hosts.pocket-tmp && mv /etc/hosts.pocket-tmp /etc/hosts
        fi
      '';
    };

    systemd.tmpfiles.settings."10-pocket-box-name".${stateDir}.d = { mode = "0755"; user = "root"; group = "root"; };

    systemd.services.pocket-box-name = {
      description = "Pocket Box public name and certificate";
      after = [ "network-online.target" "caddy.service" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${names} ${namesConfig}";
        TimeoutStartSec = "20min";
      };
    };

    # Until the box has its name: try every 3 minutes, so a new box (or one that was offline at first)
    # gets it within minutes. The same program; its lock keeps the two from running at once.
    systemd.services.pocket-box-name-soon = {
      description = "Pocket Box public name, until it has one";
      after = [ "network-online.target" "caddy.service" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "!${stateDir}/domain";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${names} ${namesConfig}";
        TimeoutStartSec = "20min";
      };
    };
    systemd.timers.pocket-box-name-soon = {
      description = "Pocket Box public name, until it has one";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitInactiveSec = "3min";
      };
    };

    systemd.timers.pocket-box-name = {
      description = "Pocket Box public name and certificate";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Soon after boot, without the usual random delay: a new box should have its name in minutes.
        OnBootSec = "15s";
        OnUnitActiveSec = "30min";
      };
    };
  };
}
