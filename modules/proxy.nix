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

  landing = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Pocket Box</title>
    <style>
      :root { color-scheme: light dark; --fg: #1d1d1f; --muted: #6e6e73; --card: #fff; --bg: #f5f5f7; --accent: #0a84ff; }
      @media (prefers-color-scheme: dark) { :root { --fg: #f5f5f7; --muted: #a1a1a6; --card: #1c1c1e; --bg: #000; } }
      body { margin: 0; font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--fg); }
      main { max-width: 560px; margin: 0 auto; padding: 40px 20px; }
      h1 { font-size: 28px; margin: 0 0 4px; }
      p.lead { color: var(--muted); margin: 0 0 28px; }
      p.note { color: var(--muted); font-size: 14px; margin: 0 0 8px; }
      #blocked { margin-bottom: 20px; }
      section { background: var(--card); border-radius: 16px; padding: 20px; margin-bottom: 16px; }
      h2 { font-size: 18px; margin: 0 0 8px; }
      a.button { display: inline-block; background: var(--accent); color: #fff; text-decoration: none; padding: 10px 18px; border-radius: 10px; font-weight: 600; margin: 6px 0 12px; }
      details { margin-top: 6px; } summary { cursor: pointer; font-weight: 600; }
      details p, li { color: var(--muted); font-size: 15px; }
      ol { padding-left: 20px; margin: 6px 0; }
      .spin { display: inline-block; width: 18px; height: 18px; border: 2.5px solid var(--muted); border-top-color: var(--accent); border-radius: 50%; animation: spin 0.9s linear infinite; vertical-align: -3px; margin-right: 8px; }
      @keyframes spin { to { transform: rotate(360deg); } }
      @media (prefers-reduced-motion: reduce) { .spin { animation: none; } }
      button.link { background: none; border: 0; padding: 0; color: var(--accent); font: inherit; cursor: pointer; text-decoration: underline; }
      .choice { display: block; background: var(--card); border: 2px solid transparent; border-radius: 16px; padding: 16px 18px 16px 48px; margin-bottom: 12px; cursor: pointer; position: relative; }
      .choice:has(input:checked) { border-color: var(--accent); }
      .choice input { position: absolute; left: 18px; top: 19px; width: 18px; height: 18px; accent-color: var(--accent); margin: 0; }
      .choice b { display: block; font-size: 17px; }
      .choice > span { color: var(--muted); font-size: 15px; }
      .tag { display: inline-block; background: var(--accent); color: #fff; font-size: 12px; font-weight: 600; border-radius: 6px; padding: 1px 7px; margin-left: 6px; vertical-align: 2px; }
      button.primary { background: var(--accent); color: #fff; border: 0; padding: 11px 20px; border-radius: 10px; font: inherit; font-weight: 600; cursor: pointer; margin: 6px 0 4px; }
      button.primary:disabled { opacity: .55; cursor: default; }
      label.field { display: block; font-weight: 600; margin: 12px 0 4px; }
      input.text, select.text { width: 100%; box-sizing: border-box; font: inherit; padding: 9px 11px; border-radius: 10px; border: 1px solid var(--muted); background: var(--bg); color: var(--fg); }
      .row { display: flex; align-items: center; gap: 6px; } .row input.text { flex: 1; } .row .suffix { color: var(--muted); white-space: nowrap; }
      p.error { color: #d70015; font-size: 15px; margin: 8px 0 0; }
      @media (prefers-color-scheme: dark) { p.error { color: #ff6961; } }
      hr { border: 0; border-top: 1px solid var(--bg); margin: 16px 0; }
    </style>
    </head>
    <body>
    <main>
      <h1>Pocket Box</h1>
      <section id="opening" hidden>
        <h2>Opening Pocket Box…</h2>
        <p>If nothing happens, <a id="opening-link" href="#">open it here</a>.</p>
      </section>
      <div id="choose" hidden>
        <p class="lead">How should your box get its padlock? You can change this later in Pocket Core → Settings → This box.</p>
        <label class="choice"><input type="radio" name="mode" value="pocket" checked>
          <b>Pocket's free address<span class="tag">Recommended</span></b>
          <span>Ready in about a minute, nothing to install. Your box gets a name like x7k2m9.box.pockethomelab.com, pointing at its home address.</span></label>
        <label class="choice"><input type="radio" name="mode" value="cloudflare">
          <b>My own domain on Cloudflare</b>
          <span>Like pocket.yourname.com. Sign in with Cloudflare and the box sets up the rest itself; nothing goes through Pocket's servers.</span></label>
        <label class="choice"><input type="radio" name="mode" value="own-ca">
          <b>The box's own certificate</b>
          <span>No name on the internet at all. Install the box's certificate once on each phone and computer; works without internet.</span></label>
        <button type="button" class="primary" id="choose-go">Continue</button>
        <p class="error" id="choose-error" hidden></p>
      </div>
      <section id="cf" hidden>
        <h2>Your own domain on Cloudflare</h2>
        <p>You need a domain whose DNS is on Cloudflare (the free plan is enough). The box adds two records to it,
          <i>name</i>.yourdomain and *.<i>name</i>.yourdomain, pointing at its home address, and gets its certificate itself.</p>
        <div id="cf-signin">
          <div id="cf-oauth" hidden>
            <button type="button" class="primary" id="cf-oauth-go">Sign in with Cloudflare</button>
            <p class="note">Cloudflare asks you to allow “Pocket Box” to read your domains and edit their DNS.</p>
            <hr>
            <p class="note"><button type="button" class="link" id="cf-token-show">Use an API token instead</button></p>
          </div>
          <div id="cf-token">
            <p><b>1.</b> <a href="#" id="cf-token-link" target="_blank" rel="noopener">Create a token in Cloudflare</a>. The permissions are filled in already
              (Zone · Read and DNS · Edit); press <i>Continue to summary</i>, then <i>Create Token</i>.</p>
            <label class="field" for="cf-token-in"><b>2.</b> Paste the token here</label>
            <input class="text" id="cf-token-in" autocomplete="off" spellcheck="false" placeholder="The token Cloudflare shows once">
            <button type="button" class="primary" id="cf-token-go">Next</button>
          </div>
        </div>
        <div id="cf-zone" hidden>
          <label class="field" for="cf-zone-in">Domain</label>
          <select class="text" id="cf-zone-in"></select>
          <label class="field" for="cf-sub-in">Name for the box</label>
          <div class="row"><input class="text" id="cf-sub-in" value="pocket" autocomplete="off" spellcheck="false"><span class="suffix" id="cf-suffix"></span></div>
          <p class="note" id="cf-preview"></p>
          <button type="button" class="primary" id="cf-use">Use this address</button>
        </div>
        <p class="error" id="cf-error" hidden></p>
        <p class="note"><button type="button" class="link" id="cf-back">Back to the choices</button></p>
      </section>
      <section id="getting" hidden>
        <h2><span class="spin" aria-hidden="true"></span>Getting your box's secure address…</h2>
        <p id="getting-what">This takes a minute or two. The page moves on by itself; nothing to install.</p>
        <p class="note">Can't wait? <button type="button" class="link" id="now">Use the box now</button> by installing its certificate instead.</p>
      </section>
      <div id="steps">
      <p class="lead">Two steps on each phone or computer you use with the box.</p>
      <p class="note" id="why" hidden></p>
      <p class="note" id="blocked" hidden>This network can't reach the box's own address (<span id="blocked-name"></span>);
        some routers block names that point into the home network. Until the router allows it, use the steps below.</p>
      <section>
        <h2>1. Trust the box's certificate</h2>
        <p>The box encrypts everything with its own certificate. Install it once so your browser trusts it.</p>
        <a class="button" href="/pocket-box-ca.crt">Download certificate</a>
        <p class="note">If the browser says “Insecure download blocked”, choose Keep: this page can't use https until the certificate is installed.</p>
        <details><summary>iPhone and iPad</summary><ol>
          <li>Open the download, then Settings → Profile Downloaded → Install.</li>
          <li>Settings → General → About → Certificate Trust Settings → turn on “Pocket Box”.</li></ol></details>
        <details><summary>Mac</summary><ol>
          <li>Open the file; Keychain Access adds it to the login keychain.</li>
          <li>Double-click “Pocket Box” → Trust → When using this certificate: Always Trust.</li></ol></details>
        <details><summary>Android</summary><ol>
          <li>Settings → Security → More security settings → Install from storage → CA certificate.</li>
          <li>Pick the downloaded file.</li></ol></details>
        <details><summary>Windows</summary><ol>
          <li>Open the file → Install Certificate → Local Machine.</li>
          <li>Place it in “Trusted Root Certification Authorities”.</li></ol></details>
      </section>
      <section>
        <h2>2. Open Pocket Core</h2>
        <p>Create your account there; it lists every app on the box.</p>
        <a class="button" href="${url.site "core"}">Open Pocket Core</a>
      </section>
      <p class="note" id="steps-change" hidden>Rather have an address every browser trusts? Choose it in Pocket Core → Settings → This box.</p>
      </div>
    </main>
    <script>
      // First the owner chooses how the box gets its padlock (Pocket's address, their own domain on
      // Cloudflare, or the box's own certificate). Once the box has a public name, go there instead,
      // if this network can reach it. While the box is still getting it, wait rather than offer the
      // certificate steps.
      const $ = (id) => document.getElementById(id);
      const VIEWS = ["opening", "choose", "cf", "getting", "steps"];
      const show = (view) => { for (const v of VIEWS) $(v).hidden = v !== view; };
      const get = async (path) => {
        try {
          const r = await fetch(path, { cache: "no-store" });
          return r.ok ? await r.json() : null;
        } catch (e) { return null; }
      };
      const send = async (method, path, body) => {
        try {
          const r = await fetch("/box-address" + path, { method, cache: "no-store",
            headers: { "Content-Type": "application/json", "X-Pocket-Box": "1" }, body: JSON.stringify(body || {}) });
          const data = await r.json().catch(() => ({}));
          if (!r.ok) throw new Error(data.error || "The box didn't answer (" + r.status + ").");
          return data;
        } catch (e) {
          throw new Error(e instanceof TypeError ? "The box didn't answer. Is this device on the same network?" : e.message);
        }
      };
      const fail = (id, e) => { $(id).textContent = e ? e.message || String(e) : ""; $(id).hidden = !e; };
      const busy = (btn, on, text) => { btn.disabled = on; if (text) btn.textContent = text; };
      const WHAT = {
        asking: "Asking for its address. This takes a minute or two; the page moves on by itself.",
        certificate: "Almost there: getting its certificate. The page moves on by itself.",
        waiting: "Waiting for its address; the box asks again every few minutes and the page moves on by itself.",
      };
      let gaveUp = false, polling = false, addr = null, signin = {};
      const opened = Date.now();
      $("now").onclick = () => { gaveUp = true; show("steps"); };

      async function open(name) {
        show("opening");
        $("opening-link").href = name.core + "/";
        const stop = new AbortController();
        setTimeout(() => stop.abort(), 5000);
        try {
          await fetch(name.core + "/healthz", { mode: "no-cors", cache: "no-store", signal: stop.signal });
          location.replace(name.core + "/");
        } catch (e) {
          show("steps");
          $("blocked-name").textContent = name.domain;
          $("blocked").hidden = false;
        }
      }

      // ---- the choice ----
      $("choose-go").onclick = async () => {
        const mode = document.querySelector("input[name=mode]:checked").value;
        fail("choose-error");
        if (mode === "cloudflare") return showCloudflare();
        busy($("choose-go"), true);
        try {
          await send("PUT", "/v1/address", { mode });
          if (mode === "own-ca") { gaveUp = true; show("steps"); $("steps-change").hidden = false; }
          else { $("getting-what").textContent = WHAT.asking; show("getting"); poll(); }
        } catch (e) { fail("choose-error", e); }
        busy($("choose-go"), false);
      };

      function showCloudflare() {
        fail("cf-error");
        $("cf-token-link").href = (addr && addr.options && addr.options.token_link) || "https://dash.cloudflare.com/profile/api-tokens";
        const oauth = !!(addr && addr.options && addr.options.oauth);
        $("cf-oauth").hidden = !oauth;
        $("cf-token").hidden = oauth;
        $("cf-signin").hidden = false;
        $("cf-zone").hidden = true;
        show("cf");
      }
      $("cf-back").onclick = () => show("choose");
      $("cf-token-show").onclick = () => { $("cf-token").hidden = false; $("cf-oauth").hidden = true; };
      $("cf-oauth-go").onclick = async () => {
        fail("cf-error");
        busy($("cf-oauth-go"), true);
        try { location.href = (await send("POST", "/v1/address/cloudflare/start", {})).url; }
        catch (e) { fail("cf-error", e); busy($("cf-oauth-go"), false); }
      };
      $("cf-token-go").onclick = async () => {
        const token = $("cf-token-in").value.trim();
        fail("cf-error");
        if (!token) return fail("cf-error", new Error("Paste the token first."));
        busy($("cf-token-go"), true);
        try { showZones((await send("POST", "/v1/address/cloudflare/zones", { token })).zones, { token }); }
        catch (e) { fail("cf-error", e); }
        busy($("cf-token-go"), false);
      };

      function preview() {
        const z = $("cf-zone-in").selectedOptions[0];
        const sub = $("cf-sub-in").value.trim().toLowerCase() || "pocket";
        $("cf-suffix").textContent = z ? "." + z.textContent : "";
        $("cf-preview").textContent = z ? "Pocket Core will be at https://core." + sub + "." + z.textContent : "";
      }
      $("cf-zone-in").onchange = preview;
      $("cf-sub-in").oninput = () => { fail("cf-error"); preview(); };

      function showZones(zones, how) {
        signin = how;
        show("cf");
        if (!zones.length) {
          $("cf-signin").hidden = false;
          return fail("cf-error", new Error("This sign-in can't change any domain. Add your domain to Cloudflare first, or give the token access to it."));
        }
        $("cf-zone-in").replaceChildren(...zones.map((z) => { const o = document.createElement("option"); o.value = z.id; o.textContent = z.name; return o; }));
        $("cf-signin").hidden = true;
        $("cf-zone").hidden = false;
        preview();
      }
      $("cf-use").onclick = async () => {
        fail("cf-error");
        busy($("cf-use"), true);
        try {
          await send("PUT", "/v1/address", { mode: "cloudflare", zone_id: $("cf-zone-in").value, sub: $("cf-sub-in").value.trim().toLowerCase(), ...signin });
          $("getting-what").textContent = "Setting up " + $("cf-sub-in").value.trim().toLowerCase() + "." + $("cf-zone-in").selectedOptions[0].textContent + ". This takes a minute or two; the page moves on by itself.";
          show("getting");
          poll();
        } catch (e) { fail("cf-error", e); }
        busy($("cf-use"), false);
      };

      // Back from "Sign in with Cloudflare" (through names.pockethomelab.com, with the code).
      async function cloudflareBack(q) {
        history.replaceState(null, "", "/");
        addr = await get("/box-address/v1/address");
        showCloudflare();
        if (q.get("error")) return fail("cf-error", new Error("Cloudflare didn't sign you in (" + (q.get("error_description") || q.get("error")) + ")."));
        try {
          const r = await send("POST", "/v1/address/cloudflare/finish", { code: q.get("code"), state: q.get("state") });
          showZones(r.zones, { pending: r.pending });
        } catch (e) { fail("cf-error", e); }
      }

      // ---- waiting for the name ----
      function poll() { if (!polling) { polling = true; check(); } }

      async function check() {
        polling = false;
        const name = await get("/name.json");
        if (name) return open(name);
        addr = await get("/box-address/v1/address");
        if (addr && addr.mode === null && addr.can_choose) {
          if ($("choose").hidden && $("cf").hidden) show("choose");
          return;
        }
        if (addr && (addr.mode === "own-ca" || addr.mode === "off")) {
          show("steps");
          $("steps-change").hidden = addr.mode !== "own-ca";
          return;
        }
        const st = (addr && addr.status && addr.status.state ? addr.status : null) || await get("/name-status.json");
        const fresh = st && Date.now() / 1000 - st.at < 45 * 60;
        $("why").hidden = true;
        const tooLong = st && st.state === "waiting" && Date.now() - opened > 10 * 60 * 1000;
        if (!gaveUp && fresh && WHAT[st.state] && !tooLong) {
          // Keep "Setting up pocket.example.com…" while it asks; say what comes next after that.
          if (st.state !== "asking" || $("getting").hidden) $("getting-what").textContent = WHAT[st.state];
          show("getting");
        } else if (!gaveUp) {
          show("steps");
          if (st && fresh && st.message && (["offline", "failed", "signin"].includes(st.state) || tooLong)) {
            $("why").textContent = st.message + " Until then, use the steps below; the page moves on by itself once the box has its address.";
            $("why").hidden = false;
          }
        }
        // Keep looking while the box may still get its name (no status yet: it has only just started).
        if (!st || ["asking", "certificate", "waiting", "offline", "failed", "signin", "choose"].includes(st.state)) {
          polling = true;
          setTimeout(check, 4000);
        }
      }

      const q = new URLSearchParams(location.search);
      if (q.get("code") || q.get("error")) cloudflareBack(q); else poll();
    </script>
    </body>
    </html>
  '';

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
