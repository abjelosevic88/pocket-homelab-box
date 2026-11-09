# The box's public name: <random>.box.pockethomelab.com with a Let's Encrypt certificate, so phones
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

    # The landing page asks for this to send a browser on to the public name.
    services.caddy.virtualHosts."http://${box.domain}".extraConfig = lib.mkBefore ''
      handle /name.json {
        header Cache-Control no-store
        root * ${stateDir}/public
        file_server
      }
    '';

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

    systemd.timers.pocket-box-name = {
      description = "Pocket Box public name and certificate";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30min";
        RandomizedDelaySec = "2min";
      };
    };
  };
}
