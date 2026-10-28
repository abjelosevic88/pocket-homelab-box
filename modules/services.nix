# Third-party services some Pocket apps sit on top of, from the NixOS modules in nixpkgs:
#   Jellyfin   → Pocket Watch, Pocket Subtitles     https://jellyfin.<domain>
#   Navidrome  → Pocket Music                       https://navidrome.<domain>
#   Immich     → Pocket Photos                      https://immich.<domain>
#   OnlyOffice → Pocket Office                      https://onlyoffice.<domain>
# Each is on by default, listens on loopback behind Caddy and is wired to its app by URL.
# On first boot pocket-box-backends makes a box administrator and key in Jellyfin, Navidrome and
# Immich and hands them to Pocket Core (SERVICES_FILE), whose connectors then give every person
# their own account and key there, which Pocket Watch, Music and Photos use.
{ config, lib, pkgs, ... }:

let
  box = config.pocket.box;
  cfg = box.services;
  url = import ./urls.nix box;
  localUrl = port: "http://127.0.0.1:${toString port}";
  media = "/srv/media";
  ooSecrets = "/var/lib/onlyoffice-secrets";
  ooPort = 8166;
  hasApp = slug: lib.elem slug box.apps;

  servicesFile = "/var/lib/pocket-box/core-services.json";
  managed = lib.filter (s: s.enable) [
    { type = "jellyfin"; port = 8096; unit = "jellyfin.service"; enable = cfg.jellyfin.enable; }
    { type = "navidrome"; port = 4533; unit = "navidrome.service"; enable = cfg.navidrome.enable; }
    { type = "immich"; port = 2283; unit = "immich-server.service"; enable = cfg.immich.enable; }
  ];
  bootstrapConfig = pkgs.writeText "pocket-box-backends.json" (builtins.toJSON {
    state_dir = "/var/lib/pocket-box/backends";
    services_file = servicesFile;
    media_dir = media;
    inherit (box) domain;
    services = map (s: { inherit (s) type; url = localUrl s.port; public_url = url.site s.type; }) managed;
  });
  bootstrap = pkgs.writers.writePython3 "pocket-box-backends" { flakeIgnore = [ "E501" ]; }
    (builtins.readFile ./backends-bootstrap.py);
in
{
  options.pocket.box.services = {
    jellyfin.enable = lib.mkOption { type = lib.types.bool; default = true; description = "Jellyfin, for Pocket Watch."; };
    navidrome.enable = lib.mkOption { type = lib.types.bool; default = true; description = "Navidrome, for Pocket Music."; };
    immich.enable = lib.mkOption { type = lib.types.bool; default = true; description = "Immich, for Pocket Photos."; };
    onlyoffice.enable = lib.mkOption { type = lib.types.bool; default = true; description = "OnlyOffice Document Server, for Pocket Office."; };
  };

  config = lib.mkIf box.enable (lib.mkMerge [
    {
      # Box administrators and keys in the services, then the file Pocket Core reads at start.
      systemd.services.pocket-box-backends = {
        description = "Set up the Pocket Box's media and photo services for Pocket Core";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "pocket-box-secrets.service" ] ++ map (s: s.unit) managed;
        wants = [ "network-online.target" ] ++ map (s: s.unit) managed;
        before = [ "pocket-core.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${bootstrap} ${bootstrapConfig}";
          TimeoutStartSec = "20min";
          UMask = "0077";
        };
      };
      # Core refuses to start without its credential file; an empty list until the services are ready.
      systemd.tmpfiles.settings."10-pocket-box-services" = {
        "/var/lib/pocket-box".d = { mode = "0700"; user = "root"; group = "root"; };
        "${servicesFile}".f = { mode = "0600"; user = "root"; group = "root"; argument = "[]"; };
      };
      systemd.services.pocket-core = {
        after = [ "pocket-box-backends.service" ];
        wants = [ "pocket-box-backends.service" ];
        environment.SERVICES_FILE = "%d/services.json";
        serviceConfig.LoadCredential = [ "services.json:${servicesFile}" ];
      };
    }

    (lib.mkIf cfg.jellyfin.enable {
      # Jellyfin has no listen-address option; it binds every interface, but only 80/443 are open.
      services.jellyfin.enable = true;
      pocket.box.sites.jellyfin = 8096;
      users.users.jellyfin.extraGroups = [ "pocket-media" ];
      systemd.services.pocket-watch.environment = lib.mkIf (hasApp "watch") {
        JELLYFIN_URL = localUrl 8096;
        JELLYFIN_PUBLIC_URL = url.site "jellyfin";
      };
      systemd.services.pocket-subtitles.environment = lib.mkIf (hasApp "subtitles") {
        JELLYFIN_URL = localUrl 8096;
      };
    })

    (lib.mkIf cfg.navidrome.enable {
      services.navidrome = {
        enable = true;
        settings = {
          Address = "127.0.0.1";
          Port = 4533;
          MusicFolder = "${media}/music";
          # nixpkgs points the plugin folder into the read-only store, and with no plugins bundled
          # Navidrome dies trying to create it.
          Plugins.Enabled = false;
        };
      };
      pocket.box.sites.navidrome = 4533;
      systemd.services.pocket-music.environment = lib.mkIf (hasApp "music") {
        NAVIDROME_URL = localUrl 4533;
        NAVIDROME_PUBLIC_URL = url.site "navidrome";
      };
    })

    (lib.mkIf cfg.immich.enable {
      services.immich = { enable = true; host = "127.0.0.1"; port = 2283; };
      pocket.box.sites.immich = 2283;
      systemd.services.pocket-photos.environment = lib.mkIf (hasApp "photos") {
        IMMICH_URL = localUrl 2283;
        IMMICH_PUBLIC_URL = url.site "immich";
      };
    })

    (lib.mkIf cfg.onlyoffice.enable {
      services.onlyoffice = {
        enable = true;
        hostname = url.host "onlyoffice";
        # Pocket Office runs on the same box, so the Document Server must be allowed to call it back.
        allowLocalConnections = true;
        jwtSecretFile = "${ooSecrets}/jwt";
        securityNonceFile = "${ooSecrets}/nonce.conf";
      };
      services.nginx.virtualHosts.${url.host "onlyoffice"} = {
        default = true;
        listen = [ { addr = "127.0.0.1"; port = ooPort; } ];
      };
      pocket.box.sites.onlyoffice = ooPort;

      # The Document Server and Pocket Office share a JWT secret, made on the first boot.
      systemd.services.pocket-box-onlyoffice-secrets = {
        description = "OnlyOffice secrets for the Pocket Box";
        wantedBy = [ "multi-user.target" ];
        before = [ "nginx.service" "onlyoffice-docservice.service" "onlyoffice-converter.service" "pocket-office.service" ];
        requiredBy = [ "nginx.service" "onlyoffice-docservice.service" "onlyoffice-converter.service" ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; UMask = "0027"; };
        path = [ pkgs.coreutils ];
        script = ''
          mkdir -p ${ooSecrets}
          chgrp onlyoffice ${ooSecrets}
          chmod 0750 ${ooSecrets}
          rand() { head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40; }
          if [ ! -s ${ooSecrets}/jwt ]; then
            rand > ${ooSecrets}/jwt.tmp && mv ${ooSecrets}/jwt.tmp ${ooSecrets}/jwt
          fi
          if [ ! -s ${ooSecrets}/nonce.conf ]; then
            printf 'set $secure_link_secret "%s";\n' "$(rand)" > ${ooSecrets}/nonce.tmp && mv ${ooSecrets}/nonce.tmp ${ooSecrets}/nonce.conf
          fi
          chgrp onlyoffice ${ooSecrets}/jwt ${ooSecrets}/nonce.conf
          chmod 0640 ${ooSecrets}/jwt ${ooSecrets}/nonce.conf
          printf 'ONLYOFFICE_JWT_SECRET=%s\n' "$(cat ${ooSecrets}/jwt)" > ${ooSecrets}/office.env
          chmod 0600 ${ooSecrets}/office.env
          chgrp root ${ooSecrets}/office.env
        '';
      };

      systemd.services.pocket-office = lib.mkIf (hasApp "office") {
        after = [ "pocket-box-onlyoffice-secrets.service" ];
        requires = [ "pocket-box-onlyoffice-secrets.service" ];
        environment = {
          ONLYOFFICE_URL = url.site "onlyoffice";
          ONLYOFFICE_INTERNAL_URL = localUrl ooPort;
          ONLYOFFICE_JWT_HEADER = "Authorization";
          CALLBACK_URL = localUrl 8186;
        };
        serviceConfig.EnvironmentFile = [ "${ooSecrets}/office.env" ];
      };
    })
  ]);
}
