# The box's front door. Caddy serves every app and service at https://<name>.<domain> with
# certificates from its own local CA ("Pocket Box"), and the bare domain over plain http as a
# landing page where a phone or laptop downloads that CA once. Names under .local are announced over
# mDNS, the box resolves them itself through /etc/hosts, and the apps trust the CA through
# SSL_CERT_FILE so they can reach each other (and Core's OIDC) by their public names.
{ config, lib, pkgs, ... }:

let
  cfg = config.pocket.box;
  url = import ./urls.nix cfg;
  names = lib.mapAttrsToList (name: _: url.host name) cfg.sites;
  caddyRoot = "/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt";

  # The page itself is modules/landing.html; @CORE_URL@ becomes Pocket Core's address.
  landing = pkgs.writeTextDir "index.html"
    (builtins.replaceStrings [ "@CORE_URL@" ] [ (url.site "core") ] (builtins.readFile ./landing.html));

  # Announces every <name>.<domain> over mDNS on each interface's IPv4 address, and again when the
  # addresses change. Avahi itself only announces the host name.
  mdnsAliases = pkgs.writers.writePython3 "pocket-box-mdns-aliases"
    { libraries = [ pkgs.python3Packages.dbus-python ]; flakeIgnore = [ "E501" ]; } ''
    import json
    import subprocess
    import sys
    import time

    import dbus

    NAMES = sys.argv[1:]
    PROTO_INET = 0
    NO_REVERSE = 16

    bus = dbus.SystemBus()
    server = dbus.Interface(bus.get_object("org.freedesktop.Avahi", "/"), "org.freedesktop.Avahi.Server")


    def addresses():
        out = json.loads(subprocess.check_output(["${pkgs.iproute2}/bin/ip", "-j", "-4", "addr", "show", "scope", "global"]))
        return sorted(
            (i["ifindex"], a["local"])
            for i in out
            if not i["ifname"].startswith(("docker", "veth", "br-", "virbr", "tailscale"))
            for a in i.get("addr_info", [])
            if a.get("family") == "inet"
        )


    # Avahi allows 32 entries per group, so the records are spread over several groups.
    PER_GROUP = 25

    groups, current = [], None
    while True:
        now = addresses()
        if now != current:
            for group in groups:
                group.Free()
            groups = []
            records = [(index, address, name) for index, address in now for name in NAMES]
            for start in range(0, len(records), PER_GROUP):
                group = dbus.Interface(bus.get_object("org.freedesktop.Avahi", server.EntryGroupNew()), "org.freedesktop.Avahi.EntryGroup")
                for index, address, name in records[start:start + PER_GROUP]:
                    group.AddAddress(dbus.Int32(index), dbus.Int32(PROTO_INET), dbus.UInt32(NO_REVERSE), name, address)
                group.Commit()
                groups.append(group)
            if now:
                print("announced", len(NAMES), "names on", ", ".join(a for _, a in now), flush=True)
            current = now
        time.sleep(15)
  '';
in
{
  options.pocket.box.sites = lib.mkOption {
    type = lib.types.attrsOf lib.types.port;
    default = { };
    internal = true;
    description = "Name → loopback port. Each becomes https://<name>.<domain> through Caddy.";
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      globalConfig = ''
        http_port ${toString cfg.httpPort}
        https_port ${toString cfg.httpsPort}
        skip_install_trust
        pki {
          ca local {
            name "Pocket Box"
            root_cn "Pocket Box Root CA"
            intermediate_cn "Pocket Box Intermediate CA"
          }
        }
      '';
      virtualHosts = {
        # Plain http on purpose: a device that does not trust the box yet must still reach this page.
        "http://${cfg.domain}".extraConfig = ''
          handle /pocket-box-ca.crt {
            header Content-Type application/x-x509-ca-cert
            header Content-Disposition "attachment; filename=pocket-box-ca.crt"
            root * ${url.caDir}
            file_server
          }
          handle {
            root * ${landing}
            file_server
          }
        '';
        "https://${cfg.domain}".extraConfig = ''
          tls internal
          redir ${url.site "core"}{uri}
        '';
      } // lib.mapAttrs' (name: port: lib.nameValuePair "https://${url.host name}" {
        extraConfig = ''
          tls internal
          reverse_proxy 127.0.0.1:${toString port}
        '';
      }) cfg.sites;
    };

    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort ];

    # The box reaches its own names without mDNS.
    networking.hosts."127.0.0.1" = [ cfg.domain ] ++ names;

    # Copies Caddy's root CA where the landing page serves it, and builds the bundle the apps trust.
    systemd.services.pocket-box-ca = {
      description = "Pocket Box certificate authority for the apps";
      after = [ "caddy.service" ];
      wants = [ "caddy.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      path = [ pkgs.coreutils ];
      script = ''
        for _ in $(seq 120); do [ -s ${caddyRoot} ] && break; sleep 1; done
        if [ ! -s ${caddyRoot} ]; then echo "Caddy made no root CA" >&2; exit 1; fi
        install -d -m 0755 ${url.caDir}
        install -m 0644 ${caddyRoot} ${url.caCert}
        cat /etc/ssl/certs/ca-certificates.crt ${caddyRoot} > ${url.caBundle}.tmp
        chmod 0644 ${url.caBundle}.tmp
        mv ${url.caBundle}.tmp ${url.caBundle}
      '';
    };

    # NixOS turns off publishing over Avahi's D-Bus API, which the announcer below uses.
    services.avahi.settings.publish.disable-user-service-publishing = lib.mkIf (lib.hasSuffix ".local" cfg.domain) false;

    systemd.services.pocket-box-mdns-aliases = lib.mkIf (lib.hasSuffix ".local" cfg.domain) {
      description = "Announce the Pocket Box app names over mDNS";
      after = [ "avahi-daemon.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      bindsTo = [ "avahi-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${mdnsAliases} ${lib.escapeShellArgs names}";
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [ "AF_UNIX" "AF_NETLINK" ];
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
