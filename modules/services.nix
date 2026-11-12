# Third-party services some Pocket apps sit on top of, from the NixOS modules in nixpkgs:
#   Jellyfin   → Pocket Watch, Pocket Subtitles     https://jellyfin.<domain>
#   Navidrome  → Pocket Music                       https://navidrome.<domain>
#   Immich     → Pocket Photos                      https://immich.<domain>
#   OnlyOffice → Pocket Office                      https://onlyoffice.<domain>
# Each is on by default, listens on loopback behind Caddy and is wired to its app by URL.
# Two more only their app talks to, on loopback with no site of their own:
#   SearXNG    → Pocket Search  (its search engine)          127.0.0.1:8888
#   Chromium   → Pocket Lookout (pages that need JavaScript)  127.0.0.1:9222
#   guacd      → Pocket Remote  (VNC, RDP and SSH)            127.0.0.1:4822
#   LibreTranslate → Pocket Translate (offline engine, off by default) 127.0.0.1:5000
# The download services behind Pocket Watch, Requests and Subtitles, loopback only and without a site
# (Pocket Requests shows what the owner needs of them; Core → Settings → System → Downloads sets them up):
#   Radarr 7878, Sonarr 8989, Prowlarr 9696, SABnzbd 8085   with watch or requests
#   Lidarr 8686                                             with requests and music
#   Bazarr 6767                                             with subtitles
# Their API keys are made by the box (pocket-box-media-keys) before they first start, so the box knows
# every key; pocket-box-backends wires them to each other, pocket-box-downloads (modules/downloads.py)
# takes the owner's Usenet provider, indexers and subtitle languages from Core.
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
  searxEnv = "/var/lib/pocket-box/searx.env";
  hasApp = slug: lib.elem slug box.apps;

  # The download services: keys made by the box, kept root-only in keysDir.
  keysDir = "/var/lib/pocket-box/media-keys";
  downloads = "${media}/downloads";
  arrPorts = { radarr = 7878; sonarr = 8989; lidarr = 8686; prowlarr = 9696; sabnzbd = 8085; bazarr = 6767; qbittorrent = 8090; };
  arrTypes = lib.filter (t: cfg.${t}.enable) [ "sabnzbd" "radarr" "sonarr" "lidarr" "prowlarr" "bazarr" "qbittorrent" ];
  # Torrents: qBittorrent runs only while the owner has them on (Core → Downloads), and with a VPN its
  # traffic leaves only through the tunnel (pocket-box-vpn: policy routing by its user, an unreachable
  # default when the tunnel is down).
  dlState = "/var/lib/pocket-box-downloads";
  torrentsMarker = "${dlState}/torrents-on";
  vpnDir = "${dlState}/vpn";
  torrentDir = "${downloads}/torrents";
  qbProfile = "/var/lib/qBittorrent";
  # The box's own settings in qBittorrent.conf before each start: loopback, the box's login, no UPnP.
  qbPrestart = pkgs.writers.writePython3 "pocket-box-qbittorrent-config" { flakeIgnore = [ "E501" ]; } ''
    import base64
    import hashlib
    import json
    import os
    import pwd
    import re

    conf = "${qbProfile}/qBittorrent/config/qBittorrent.conf"
    password = json.load(open("${keysDir}/keys.json"))["qbittorrent"]
    text = open(conf).read() if os.path.exists(conf) else ""
    m = re.search(r"^WebUI\\Password_PBKDF2=\"?@ByteArray\(([^:]+):([^)]+)\)", text, re.M)
    salt = base64.b64decode(m.group(1)) if m else os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha512", password.encode(), salt, 100000, 64)
    want = {
        "LegalNotice": {"Accepted": "true"},
        "Preferences": {
            "WebUI\\Address": "127.0.0.1",
            "WebUI\\Port": "${toString arrPorts.qbittorrent}",
            "WebUI\\Username": "pocket-box",
            "WebUI\\Password_PBKDF2": '"@ByteArray(%s:%s)"' % (base64.b64encode(salt).decode(), base64.b64encode(digest).decode()),
            "WebUI\\LocalHostAuth": "true",
            "WebUI\\UseUPnP": "false",
            "Connection\\UPnP": "false",
            "General\\Locale": "en",
        },
    }
    sections, order, cur = {}, [], None
    for line in text.splitlines():
        h = re.match(r"^\[(.+)\]$", line)
        if h:
            cur = h.group(1)
            if cur not in sections:
                sections[cur] = []
                order.append(cur)
        elif cur is not None and line.strip():
            sections[cur].append(line)
    for sec, kv in want.items():
        if sec not in sections:
            sections[sec] = []
            order.append(sec)
        lines = [ln for ln in sections[sec] if ln.split("=", 1)[0] not in kv]
        sections[sec] = lines + ["%s=%s" % (k, v) for k, v in kv.items()]
    out = "\n".join("[%s]\n%s\n" % (sec, "\n".join(sections[sec])) for sec in order)
    os.makedirs(os.path.dirname(conf), exist_ok=True)
    with open(conf + ".tmp", "w") as f:
        f.write(out)
    u = pwd.getpwnam("qbittorrent")
    os.chown(conf + ".tmp", u.pw_uid, u.pw_gid)
    os.chmod(conf + ".tmp", 0o600)
    os.replace(conf + ".tmp", conf)
  '';
  # Radarr, Sonarr and Lidarr: loopback, the box's key, a login for the web UI (set by pocket-box-backends).
  arrSettings = name: {
    server = { bindaddress = "127.0.0.1"; port = arrPorts.${name}; };
    auth = { method = "Forms"; required = "Enabled"; };
    app.instancename = lib.toUpper (lib.substring 0 1 name) + lib.substring 1 (-1) name;
  };
  # They write into /srv/media: the media group, group-writable files, and no private user namespace
  # (it would hide the supplementary group).
  mediaWriter = {
    serviceConfig = { PrivateUsers = lib.mkForce false; UMask = lib.mkForce "0002"; SupplementaryGroups = [ "pocket-media" ]; };
    after = [ "pocket-box-media-keys.service" ];
    requires = [ "pocket-box-media-keys.service" ];
  };
  mediaKeys = pkgs.writeShellScript "pocket-box-media-keys" ''
    set -eu
    d=${keysDir}
    install -d -m 0700 "$d"
    hex() { head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
    pw() { head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32; }
    if [ ! -s "$d/keys.json" ]; then
      printf '{"radarr":"%s","sonarr":"%s","lidarr":"%s","prowlarr":"%s","sabnzbd":"%s","sabnzbd_nzb":"%s","bazarr":"%s","password":"%s"}\n' \
        "$(hex)" "$(hex)" "$(hex)" "$(hex)" "$(hex)" "$(hex)" "$(hex)" "$(pw)" > "$d/keys.json.tmp"
      mv "$d/keys.json.tmp" "$d/keys.json"
    fi
    # Keys added by later releases.
    if [ "$(jq -r '.qbittorrent // ""' "$d/keys.json")" = "" ]; then
      jq --arg v "$(pw)" '.qbittorrent = $v' "$d/keys.json" > "$d/keys.json.tmp" && mv "$d/keys.json.tmp" "$d/keys.json"
    fi
    k() { jq -r ".$1" "$d/keys.json"; }
    w() { printf '%s\n' "$2" > "$d/$1.tmp"; mv "$d/$1.tmp" "$d/$1"; }
    for a in radarr sonarr lidarr prowlarr; do
      w "$a.env" "$(echo "$a" | tr a-z A-Z)__AUTH__APIKEY=$(k "$a")"
    done
    w sabnzbd.ini "$(printf '[misc]\napi_key = %s\nnzb_key = %s\nusername = pocket-box\npassword = %s' "$(k sabnzbd)" "$(k sabnzbd_nzb)" "$(k password)")"
    w bazarr-apikey "$(k bazarr)"
    w bazarr-password "$(printf %s "$(k password)" | md5sum | cut -d' ' -f1)"
    w radarr-apikey "$(k radarr)"
    w sonarr-apikey "$(k sonarr)"
  '';

  servicesFile = "/var/lib/pocket-box/core-services.json";
  managed = lib.filter (s: s.enable) [
    { type = "jellyfin"; port = 8096; unit = "jellyfin.service"; enable = cfg.jellyfin.enable; }
    { type = "navidrome"; port = 4533; unit = "navidrome.service"; enable = cfg.navidrome.enable; }
    { type = "immich"; port = 2283; unit = "immich-server.service"; enable = cfg.immich.enable; }
  ] ++ map (t: { type = t; port = arrPorts.${t}; unit = "${t}.service"; enable = true; site = false; }) arrTypes;
  bootstrapConfig = pkgs.writeText "pocket-box-backends.json" (builtins.toJSON {
    state_dir = "/var/lib/pocket-box/backends";
    services_file = servicesFile;
    media_dir = media;
    inherit (box) domain;
    services = map (s: { inherit (s) type; url = localUrl s.port; public_url = if s.site or true then url.site s.type else ""; }) managed;
    keys_file = "${keysDir}/keys.json";
    torrents_marker = torrentsMarker;
    inherit downloads;
    # Where the arr apps reach each other (and Prowlarr reaches them).
    ports = arrPorts;
    arr = arrTypes;
  });
  # Core → Settings → System → Downloads: the owner's Usenet provider, indexers and subtitle languages.
  downloadsSocket = "/run/pocket-box-downloads/downloads.sock";
  downloadsConfig = pkgs.writeText "pocket-box-downloads.json" (builtins.toJSON {
    socket = downloadsSocket;
    group = "pocket-box-agent";
    state_dir = "/var/lib/pocket-box-downloads";
    keys_file = "${keysDir}/keys.json";
    installed = lib.any hasApp [ "watch" "requests" "subtitles" ];
    services = lib.genAttrs arrTypes (t: localUrl arrPorts.${t});
    torrents_marker = torrentsMarker;
    vpn_dir = vpnDir;
    torrent_dir = torrentDir;
    vpn_interface = "wg-pocket";
    vpn_table = 51820;
    qbittorrent_user = "qbittorrent";
    tools = {
      systemctl = "${pkgs.systemd}/bin/systemctl";
      ip = "${pkgs.iproute2}/bin/ip";
      wg = "${pkgs.wireguard-tools}/bin/wg";
      setpriv = "${pkgs.util-linux}/bin/setpriv";
      curl = "${pkgs.curl}/bin/curl";
    };
  });
  downloadsService = pkgs.writers.writePython3 "pocket-box-downloads" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./downloads.py);
  bootstrap = pkgs.writers.writePython3 "pocket-box-backends" { flakeIgnore = [ "E501" ]; }
    (builtins.readFile ./backends-bootstrap.py);
in
{
  options.pocket.box.services = {
    # Each only with the apps that use it, so a box with a few apps (Pocket Box Lite) stays small.
    jellyfin.enable = lib.mkOption { type = lib.types.bool; default = lib.any hasApp [ "watch" "subtitles" "requests" ]; defaultText = lib.literalExpression ''any of watch, subtitles, requests in config.pocket.box.apps''; description = "Jellyfin, for Pocket Watch."; };
    navidrome.enable = lib.mkOption { type = lib.types.bool; default = lib.any hasApp [ "music" "radio" "requests" ]; defaultText = lib.literalExpression ''any of music, radio, requests in config.pocket.box.apps''; description = "Navidrome, for Pocket Music."; };
    immich.enable = lib.mkOption { type = lib.types.bool; default = hasApp "photos"; defaultText = lib.literalExpression ''lib.elem "photos" config.pocket.box.apps''; description = "Immich, for Pocket Photos."; };
    onlyoffice.enable = lib.mkOption { type = lib.types.bool; default = hasApp "office"; defaultText = lib.literalExpression ''lib.elem "office" config.pocket.box.apps''; description = "OnlyOffice Document Server, for Pocket Office."; };
    searxng.enable = lib.mkOption { type = lib.types.bool; default = hasApp "search"; defaultText = lib.literalExpression ''lib.elem "search" config.pocket.box.apps''; description = "SearXNG, the search engine behind Pocket Search."; };
    browser.enable = lib.mkOption { type = lib.types.bool; default = hasApp "lookout"; defaultText = lib.literalExpression ''lib.elem "lookout" config.pocket.box.apps''; description = "A headless Chromium for Pocket Lookout."; };
    guacd.enable = lib.mkOption { type = lib.types.bool; default = hasApp "remote"; defaultText = lib.literalExpression ''lib.elem "remote" config.pocket.box.apps''; description = "guacd, the remote desktop engine behind Pocket Remote."; };
    # Off by default: it brings PyTorch (about 3.5 GiB) into the system and downloads its language models
    # on the first start. Without it Pocket Translate translates with Pocket AI.
    libretranslate.enable = lib.mkOption { type = lib.types.bool; default = false; description = "LibreTranslate, the offline engine for Pocket Translate."; };
    # The download services: Usenet only (no torrents).
    radarr.enable = lib.mkOption { type = lib.types.bool; default = lib.any hasApp [ "watch" "requests" ]; defaultText = lib.literalExpression ''any of watch, requests in config.pocket.box.apps''; description = "Radarr (films), for Pocket Requests and Watch."; };
    sonarr.enable = lib.mkOption { type = lib.types.bool; default = lib.any hasApp [ "watch" "requests" ]; defaultText = lib.literalExpression ''any of watch, requests in config.pocket.box.apps''; description = "Sonarr (shows), for Pocket Requests and Watch."; };
    prowlarr.enable = lib.mkOption { type = lib.types.bool; default = lib.any hasApp [ "watch" "requests" ]; defaultText = lib.literalExpression ''any of watch, requests in config.pocket.box.apps''; description = "Prowlarr, the NZB indexers for Radarr, Sonarr and Lidarr."; };
    sabnzbd.enable = lib.mkOption { type = lib.types.bool; default = lib.any hasApp [ "watch" "requests" ]; defaultText = lib.literalExpression ''any of watch, requests in config.pocket.box.apps''; description = "SABnzbd, the Usenet downloader."; };
    lidarr.enable = lib.mkOption { type = lib.types.bool; default = hasApp "requests" && hasApp "music"; defaultText = lib.literalExpression ''requests and music in config.pocket.box.apps''; description = "Lidarr (albums), for Pocket Requests with Pocket Music."; };
    qbittorrent.enable = lib.mkOption { type = lib.types.bool; default = lib.any hasApp [ "watch" "requests" ]; defaultText = lib.literalExpression ''any of watch, requests in config.pocket.box.apps''; description = "qBittorrent, for torrents; it runs only once the owner switches torrents on in Pocket Core → Downloads."; };
    bazarr.enable = lib.mkOption { type = lib.types.bool; default = hasApp "subtitles"; defaultText = lib.literalExpression ''lib.elem "subtitles" config.pocket.box.apps''; description = "Bazarr, which finds the subtitles Pocket Subtitles re-times."; };
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

    {
      systemd.services.pocket-box-downloads = {
        description = "Pocket Box downloads (Usenet provider, indexers and subtitles for Pocket Core)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "pocket-box-media-keys.service" ];
        before = [ "pocket-core.service" ];
        serviceConfig = {
          ExecStart = "${downloadsService} ${downloadsConfig}";
          RuntimeDirectory = "pocket-box-downloads";
          RuntimeDirectoryMode = "0750";
          StateDirectory = "pocket-box-downloads";
          StateDirectoryMode = "0700";
          Group = "pocket-box-agent";
          UMask = "0007";
          Restart = "on-failure";
          RestartSec = 3;
          NoNewPrivileges = true;
          ProtectHome = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
        };
      };
      systemd.services.pocket-core = {
        wants = [ "pocket-box-downloads.service" ];
        after = [ "pocket-box-downloads.service" ];
        environment.BOX_DOWNLOADS = downloadsSocket;
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

    (lib.mkIf cfg.searxng.enable {
      services.searx = {
        enable = true;
        environmentFile = searxEnv;
        # Only what differs from SearXNG's defaults (the same as Pocket Search's own compose file).
        settings = {
          general = {
            instance_name = "Pocket Search engine";
            donation_url = false;
            contact_url = false;
            privacypolicy_url = false;
            enable_metrics = false;
          };
          server = {
            bind_address = "127.0.0.1";
            port = 8888;
            secret_key = "$SEARX_SECRET_KEY";
            limiter = false; # only Pocket Search asks it
            public_instance = false;
            image_proxy = false; # Pocket Search proxies pictures itself
            method = "GET";
          };
          search = {
            safe_search = 1;
            autocomplete = "duckduckgo";
            default_lang = "auto";
            formats = [ "html" "json" ];
          };
          outgoing = {
            # A page waits for its slowest engine: none may hold it longer than this.
            request_timeout = 3.0;
            max_request_timeout = 10.0;
            pool_connections = 100;
            pool_maxsize = 20;
          };
          # Answers in 3-5 s and holds every video search up; people can switch it on in Settings → Engines.
          engines = [ { name = "vimeo"; disabled = true; } ];
        };
      };

      # SearXNG's secret key, made on the first boot.
      systemd.services.pocket-box-searx-secret = {
        description = "SearXNG secret for the Pocket Box";
        wantedBy = [ "multi-user.target" ];
        before = [ "searx-init.service" "searx.service" ];
        requiredBy = [ "searx-init.service" ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; UMask = "0077"; StateDirectory = "pocket-box"; StateDirectoryMode = "0700"; };
        path = [ pkgs.coreutils ];
        script = ''
          if [ ! -s ${searxEnv} ]; then
            printf 'SEARX_SECRET_KEY=%s\n' "$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)" > ${searxEnv}.tmp
            mv ${searxEnv}.tmp ${searxEnv}
          fi
        '';
      };
      systemd.services.pocket-search = lib.mkIf (hasApp "search") { after = [ "searx.service" ]; wants = [ "searx.service" ]; };
    })

    (lib.mkIf cfg.browser.enable {
      # One long-running headless Chromium; Lookout opens a tab per check and closes it.
      systemd.services.pocket-box-browser = {
        description = "Headless Chromium for Pocket Lookout";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        before = lib.optional (hasApp "lookout") "pocket-lookout.service";
        environment.HOME = "/var/lib/pocket-box-browser";
        serviceConfig = {
          # Chromium's own sandbox needs user namespaces; systemd's hardening below takes its place.
          ExecStart = lib.concatStringsSep " " [
            (lib.getExe pkgs.chromium)
            "--headless=new"
            "--no-sandbox"
            "--disable-gpu"
            "--disable-dev-shm-usage"
            "--no-first-run"
            "--no-default-browser-check"
            "--mute-audio"
            "--remote-debugging-address=127.0.0.1"
            "--remote-debugging-port=9222"
            "--user-data-dir=/var/lib/pocket-box-browser/profile"
            "about:blank"
          ];
          DynamicUser = true;
          StateDirectory = "pocket-box-browser";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/pocket-box-browser";
          Restart = "always";
          RestartSec = 3;
          MemoryMax = "1G";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
        };
      };
      systemd.services.pocket-lookout = lib.mkIf (hasApp "lookout") { after = [ "pocket-box-browser.service" ]; wants = [ "pocket-box-browser.service" ]; };
    })

    (lib.mkIf cfg.guacd.enable {
      services.guacamole-server = { enable = true; host = "127.0.0.1"; port = 4822; };
      systemd.services.pocket-remote = lib.mkIf (hasApp "remote") { after = [ "guacamole-server.service" ]; wants = [ "guacamole-server.service" ]; };
    })

    (lib.mkIf (arrTypes != [ ]) {
      # Every key the download services use, made on the first boot (root only, in keysDir).
      systemd.services.pocket-box-media-keys = {
        description = "API keys for the Pocket Box's download services";
        wantedBy = [ "multi-user.target" ];
        before = map (t: "${t}.service") arrTypes;
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = mediaKeys; UMask = "0077"; };
        path = [ pkgs.coreutils pkgs.jq ];
      };
    })

    (lib.mkIf cfg.sabnzbd.enable {
      # unrar is unfree but redistributable; SABnzbd can't unpack most Usenet posts without it.
      nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "unrar";
      services.sabnzbd = {
        enable = true;
        # The box's own settings win at every start; the Usenet servers Core adds stay in the file.
        allowConfigWrite = true;
        secretFiles = [ "/run/credentials/sabnzbd.service/keys.ini" ];
        settings = {
          misc = {
            host = "127.0.0.1";
            port = arrPorts.sabnzbd;
            download_dir = "${downloads}/incomplete";
            complete_dir = "${downloads}/complete";
            permissions = "775";
          };
          categories = lib.listToAttrs (lib.imap1 (i: c: lib.nameValuePair c { name = c; dir = c; order = i; }) [ "movies" "tv" "music" "books" ]);
        };
      };
      users.users.sabnzbd.extraGroups = [ "pocket-media" ];
      systemd.services.sabnzbd = {
        after = [ "pocket-box-media-keys.service" ];
        requires = [ "pocket-box-media-keys.service" ];
        serviceConfig = { LoadCredential = [ "keys.ini:${keysDir}/sabnzbd.ini" ]; UMask = "0002"; };
      };
      # The category folders too, so Radarr, Sonarr and Lidarr see them before the first download.
      systemd.tmpfiles.settings."10-pocket-media-downloads" = lib.genAttrs ([ downloads "${downloads}/incomplete" "${downloads}/complete" ]
        ++ map (c: "${downloads}/complete/${c}") [ "movies" "tv" "music" "books" ])
        (_: { d = { mode = "2775"; user = "root"; group = "pocket-media"; }; });
    })

    (lib.mkIf cfg.qbittorrent.enable {
      services.qbittorrent = { enable = true; webuiPort = arrPorts.qbittorrent; profileDir = qbProfile; };
      users.users.qbittorrent.extraGroups = [ "pocket-media" ];
      systemd.services.qbittorrent = {
        # Off until the owner switches torrents on (pocket-box-downloads makes the marker and starts it).
        unitConfig.ConditionPathExists = torrentsMarker;
        # Requires: no qBittorrent unless the kill switch (with a VPN) is in place.
        after = [ "pocket-box-media-keys.service" "pocket-box-vpn.service" ];
        requires = [ "pocket-box-media-keys.service" "pocket-box-vpn.service" ];
        serviceConfig = {
          ExecStartPre = [ "+${qbPrestart}" ];
          PrivateUsers = lib.mkForce false;
          SupplementaryGroups = [ "pocket-media" ];
          UMask = "0002";
          # With a VPN: the tunnel's DNS (pocket-box-vpn writes it; without a VPN the box's own).
          BindReadOnlyPaths = [ "-${vpnDir}/resolv.conf:/etc/resolv.conf" ];
        };
      };
      systemd.tmpfiles.settings."10-pocket-media-torrents" = lib.genAttrs ([ torrentDir "${torrentDir}/incomplete" "${torrentDir}/complete" ]
        ++ map (c: "${torrentDir}/complete/${c}") [ "movies" "tv" "music" "books" ])
        (_: { d = { mode = "2775"; user = "root"; group = "pocket-media"; }; });

      # The kill switch and the tunnel, from the owner's WireGuard config (if any), before qBittorrent.
      systemd.services.pocket-box-vpn = {
        description = "Pocket Box VPN for torrents (WireGuard, qBittorrent's traffic only)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        before = [ "qbittorrent.service" ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = "${downloadsService} ${downloadsConfig} vpn"; };
      };
    })

    (lib.mkIf cfg.radarr.enable {
      services.radarr = { enable = true; settings = arrSettings "radarr"; environmentFiles = [ "${keysDir}/radarr.env" ]; };
      users.users.radarr.extraGroups = [ "pocket-media" ];
      systemd.services.radarr = mediaWriter;
    })

    (lib.mkIf cfg.sonarr.enable {
      services.sonarr = { enable = true; settings = arrSettings "sonarr"; environmentFiles = [ "${keysDir}/sonarr.env" ]; };
      users.users.sonarr.extraGroups = [ "pocket-media" ];
      systemd.services.sonarr = mediaWriter;
    })

    (lib.mkIf cfg.lidarr.enable {
      services.lidarr = { enable = true; settings = arrSettings "lidarr"; environmentFiles = [ "${keysDir}/lidarr.env" ]; };
      users.users.lidarr.extraGroups = [ "pocket-media" ];
      systemd.services.lidarr = mediaWriter;
    })

    (lib.mkIf cfg.prowlarr.enable {
      services.prowlarr = { enable = true; settings = arrSettings "prowlarr"; environmentFiles = [ "${keysDir}/prowlarr.env" ]; };
      systemd.services.prowlarr = { after = [ "pocket-box-media-keys.service" ]; requires = [ "pocket-box-media-keys.service" ]; };
    })

    (lib.mkIf cfg.bazarr.enable {
      services.bazarr = {
        enable = true;
        # What the box owns (set again at every start); languages and providers are saved through its API.
        settings = {
          general = {
            ip = "127.0.0.1";
            use_radarr = cfg.radarr.enable;
            use_sonarr = cfg.sonarr.enable;
          };
          auth = {
            type = "form";
            username = "pocket-box";
            apikey._secret = "${keysDir}/bazarr-apikey";
            password._secret = "${keysDir}/bazarr-password";
          };
        } // lib.optionalAttrs cfg.radarr.enable {
          radarr = { ip = "127.0.0.1"; port = arrPorts.radarr; base_url = "/"; ssl = false; apikey._secret = "${keysDir}/radarr-apikey"; };
        } // lib.optionalAttrs cfg.sonarr.enable {
          sonarr = { ip = "127.0.0.1"; port = arrPorts.sonarr; base_url = "/"; ssl = false; apikey._secret = "${keysDir}/sonarr-apikey"; };
        };
      };
      users.users.bazarr.extraGroups = [ "pocket-media" ];
      # Subtitles go next to the films and episodes in /srv/media.
      systemd.services.bazarr = mediaWriter;
    })

    (lib.mkIf cfg.libretranslate.enable {
      services.libretranslate = {
        enable = true;
        host = "127.0.0.1";
        port = 5000;
        disableWebUI = true;
        # Fewer languages start quicker and use less memory; the same list as the app's compose file.
        extraArgs.load-only = "en,de,fr,es,it,pt,nl,pl,cs,sk,sl,bg,ru,uk,tr,sv,da,nb,fi,el,hu,ro,sq,ar,zh,ja,ko";
      };
      systemd.services.pocket-translate = lib.mkIf (hasApp "translate") {
        after = [ "libretranslate.service" ];
        wants = [ "libretranslate.service" ];
        environment.ARGOS_URL = localUrl 5000;
      };
    })
  ]);
}
