"""pocket-box-downloads: the owner's Usenet provider, NZB indexers and subtitle languages.

Pocket Core (admins only, Settings → System → Downloads) reaches this on a unix socket (group
pocket-box-agent) and it passes the settings on to the box's own services, with the keys the box made
for them (pocket-box-media-keys):

  GET    /v1/downloads              what is set up, how the last tests went, the presets
  PUT    /v1/downloads/usenet       {host, port, ssl, username, password?, connections}  → SABnzbd, tested
  DELETE /v1/downloads/usenet
  POST   /v1/downloads/indexers     {preset?, name?, url?, api_key}  → Prowlarr (Newznab), tested
  DELETE /v1/downloads/indexers/{id}
  PUT    /v1/downloads/subtitles    {languages, opensubtitles?: {username, password}}  → Bazarr
  PUT    /v1/downloads/torrents     {enabled, seeding?: {ratio, days}}  → qBittorrent started/stopped, the arr apps' client on/off
  PUT    /v1/downloads/vpn          {wireguard: "<wg-quick .conf>"}  → the tunnel for qBittorrent, tested
  DELETE /v1/downloads/vpn
  POST   /v1/downloads/indexers     {kind: "torrent", preset?, definition?, name?, url?, api_key?, username?, password?}

Torrents are off until the owner switches them on: they show the home address to other peers. With a VPN,
qBittorrent's traffic leaves only through it: pocket-box-vpn (this program with "vpn") routes everything
qBittorrent's user sends by a table of its own, whose default is the tunnel and, behind it, unreachable,
so with the tunnel down qBittorrent has no way out. The arr apps still reach its web UI on loopback.

Every change answers with the GET body. A failed test still answers 200, with status "error" and a
message in plain words; 400 is for bad input only. Passwords and API keys are never sent back.
"""
import json
import os
import pwd
import re
import socket
import socketserver
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler

CONFIG = json.load(open(sys.argv[1]))
SERVICES = dict(CONFIG["services"])  # type → http://127.0.0.1:<port>, only those on this box
QB_URL = SERVICES.pop("qbittorrent", None)  # runs only while torrents are on
T = CONFIG.get("tools", {})
MARKER = CONFIG.get("torrents_marker", "")
VPN_DIR = CONFIG.get("vpn_dir", "")
VPN_CONF = os.path.join(VPN_DIR, "wg.conf")
VPN_RESOLV = os.path.join(VPN_DIR, "resolv.conf")
IFACE = CONFIG.get("vpn_interface", "wg-pocket")
TABLE = str(CONFIG.get("vpn_table", 51820))
RULE_PRIORITY = "5000"
ADMIN = "pocket-box"
CATEGORIES = ["movies", "tv", "music", "books"]
SEEDING = {"ratio": 1.0, "days": 7}
STATE_FILE = os.path.join(CONFIG["state_dir"], "state.json")
SERVER_NAME = "usenet"
PROFILE_NAME = "Pocket Box"

# Checked on each provider's own setup pages (2026-11): the SSL host and port.
PROVIDERS = [
    {"id": "eweka", "name": "Eweka", "host": "news.eweka.nl", "port": 563, "ssl": True},
    {"id": "newshosting", "name": "Newshosting", "host": "news.newshosting.com", "port": 563, "ssl": True},
    {"id": "usenetserver", "name": "UsenetServer", "host": "news.usenetserver.com", "port": 563, "ssl": True},
    {"id": "frugal", "name": "Frugal Usenet", "host": "news.frugalusenet.com", "port": 563, "ssl": True},
    {"id": "usenetexpress", "name": "UsenetExpress", "host": "news.usenetexpress.com", "port": 563, "ssl": True},
    {"id": "easynews", "name": "Easynews", "host": "news.easynews.com", "port": 563, "ssl": True},
    {"id": "tweaknews", "name": "Tweaknews", "host": "news.tweaknews.eu", "port": 563, "ssl": True},
    {"id": "giganews", "name": "Giganews", "host": "news.giganews.com", "port": 563, "ssl": True},
]
# Prowlarr's own Newznab presets (definition = its name there), with their API addresses.
INDEXERS = [
    {"id": "nzbgeek", "name": "NZBGeek", "definition": "NZBgeek", "url": "https://api.nzbgeek.info", "signup": "https://nzbgeek.info"},
    {"id": "drunkenslug", "name": "DrunkenSlug", "definition": "DrunkenSlug", "url": "https://drunkenslug.com", "signup": "https://drunkenslug.com"},
    {"id": "nzbfinder", "name": "NZBFinder", "definition": "NZBFinder", "url": "https://nzbfinder.ws", "signup": "https://nzbfinder.ws"},
    {"id": "nzbplanet", "name": "NZBPlanet", "definition": "NzbPlanet", "url": "https://api.nzbplanet.net", "signup": "https://www.nzbplanet.net"},
    {"id": "dognzb", "name": "DOGnzb", "definition": "DOGnzb", "url": "https://api.dognzb.cr", "signup": "https://dognzb.cr"},
    {"id": "althub", "name": "altHUB", "definition": "altHUB", "url": "https://api.althub.co.za", "signup": "https://althub.co.za"},
    {"id": "ninjacentral", "name": "NinjaCentral", "definition": "NinjaCentral", "url": "https://ninjacentral.co.za", "signup": "https://ninjacentral.co.za"},
    {"id": "abnzb", "name": "abNZB", "definition": "abNZB", "url": "https://abnzb.com", "signup": "https://abnzb.com"},
]
# Public torrent sites that work in Prowlarr without FlareSolverr (checked from a box, 2026-11): the
# definition is Prowlarr's name for it.
TORRENT_INDEXERS = [
    {"id": "yts", "name": "YTS", "definition": "yts", "url": "https://yts.gg", "signup": "", "for": "films"},
    {"id": "thepiratebay", "name": "The Pirate Bay", "definition": "thepiratebay", "url": "https://thepiratebay.org", "signup": "", "for": "films, shows and music"},
    {"id": "limetorrents", "name": "LimeTorrents", "definition": "limetorrents", "url": "https://www.limetorrents.fun", "signup": "", "for": "films and shows"},
    {"id": "showrss", "name": "showRSS", "definition": "showrss", "url": "https://showrss.info", "signup": "", "for": "shows"},
    {"id": "torrentproject", "name": "TorrentProject", "definition": "torrentproject2", "url": "https://torrentproject.cc", "signup": "", "for": "films and shows"},
    {"id": "nyaa", "name": "Nyaa", "definition": "nyaasi", "url": "https://nyaa.si", "signup": "", "for": "anime"},
]
# A private tracker: Prowlarr's name for it in "definition", and the login or key it asks for.
PRIVATE_TRACKER = {"id": "private", "name": "Private tracker", "kind": "torrent", "public": False, "url": "", "signup": "",
                   "needs": ["definition", "username", "password"]}
HOST = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$")
LANG = re.compile(r"^[a-z]{2}(?:-[a-z]{2})?$")


def log(*a):
    print(*a, flush=True)


class Problem(Exception):
    """Bad input: 400 with the message."""


def keys():
    with open(CONFIG["keys_file"]) as f:
        return json.load(f)


# ---- state: how the last tests went ----

lock = threading.Lock()


def state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, ValueError):
        return {}


def save_state(st):
    tmp = STATE_FILE + ".tmp"
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        json.dump(st, f)
    os.replace(tmp, STATE_FILE)


# ---- HTTP to the services ----

class Down(Exception):
    """The service didn't answer (or refused the box's key)."""


def http(method, url, body=None, headers=None, form=None, timeout=20):
    h = {"Accept": "application/json", **(headers or {})}
    data = None
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw.decode(errors="replace")[:300]
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise Down(str(getattr(e, "reason", e))[:120])


def need(t):
    if t not in SERVICES:
        raise Problem({"sabnzbd": "SABnzbd", "prowlarr": "Prowlarr", "bazarr": "Bazarr"}.get(t, t) + " isn't on this box.")
    return SERVICES[t]


def sab(params, timeout=20):
    q = urllib.parse.urlencode({**params, "output": "json", "apikey": keys()["sabnzbd"]})
    code, out = http("GET", need("sabnzbd") + "/api?" + q, timeout=timeout)
    if code != 200 or not isinstance(out, dict):
        raise Down("SABnzbd answered %s" % code)
    if out.get("status") is False:
        raise Down("SABnzbd: " + str(out.get("error")))
    return out


def prowlarr(method, path, body=None, timeout=20):
    return http(method, need("prowlarr") + "/api/v1" + path, body, {"X-Api-Key": keys()["prowlarr"]}, timeout=timeout)


def bazarr(method, path, form=None, timeout=20):
    return http(method, need("bazarr") + "/api" + path, headers={"X-API-KEY": keys()["bazarr"]}, form=form, timeout=timeout)


def ok(code, out, what):
    if code >= 400:
        raise Down("%s answered %s: %s" % (what, code, str(out)[:200]))
    return out


# ---- the view ----

STATUS = {"sabnzbd": "/api?mode=version&output=json", "radarr": "/api/v3/system/status", "sonarr": "/api/v3/system/status",
          "lidarr": "/api/v1/system/status", "prowlarr": "/api/v1/system/status", "bazarr": "/api/system/status"}


def service_ready(t):
    k = keys()
    hdr = {"X-API-KEY": k["bazarr"]} if t == "bazarr" else {"X-Api-Key": k[t]} if t != "sabnzbd" else {}
    try:
        code, _ = http("GET", SERVICES[t] + STATUS[t], headers=hdr, timeout=5)
        return code == 200
    except Down:
        return False


def sab_servers():
    return sab({"mode": "get_config", "section": "servers"}, timeout=8).get("config", {}).get("servers", []) or []


def usenet_view(st):
    v = {"configured": False, "host": "", "port": 563, "ssl": True, "username": "", "connections": 20, "status": "untested", "message": ""}
    if "sabnzbd" not in SERVICES:
        v["message"] = "SABnzbd isn't on this box."
        return v
    try:
        servers = sab_servers()
    except Down as e:
        v.update(status="error", message="SABnzbd isn't answering (" + str(e) + ").")
        return v
    if not servers:
        return v
    s = next((x for x in servers if x.get("name") == SERVER_NAME), servers[0])
    v.update(configured=True, host=s.get("host", ""), port=int(s.get("port") or 563), ssl=bool(int(s.get("ssl") or 0)),
             username=s.get("username", ""), connections=int(s.get("connections") or 0))
    last = st.get("usenet") or {}
    if last.get("host") == v["host"] and last.get("username") == v["username"] and last.get("port") == v["port"]:
        v.update(status=last.get("status", "untested"), message=last.get("message", ""))
    if not int(s.get("enable", 1) or 0):
        v.update(status="error", message="The server is switched off in SABnzbd.")
    return v


def preset_for_url(url):
    u = url.rstrip("/").lower()
    return next((p["id"] for p in INDEXERS if p["url"].lower() == u), "")


def field(item, name):
    return next((f.get("value") for f in item.get("fields", []) if f.get("name") == name), None)


def indexers_view(st):
    if "prowlarr" not in SERVICES:
        return []
    try:
        items = ok(*prowlarr("GET", "/indexer", timeout=8), "Prowlarr")
        statuses = {s.get("indexerId"): s for s in ok(*prowlarr("GET", "/indexerstatus", timeout=8), "Prowlarr")}
    except Down:
        return []
    out = []
    known = st.get("indexers", {})
    for it in items:
        kind = it.get("protocol")
        if kind not in ("usenet", "torrent"):
            continue
        mine = known.get(str(it["id"]), {})
        status, message = mine.get("status", "ok"), mine.get("message", "")
        s = statuses.get(it["id"])
        if not it.get("enable"):
            status, message = "error", message or "Switched off in Prowlarr."
        elif s and s.get("disabledTill") and status == "ok":
            status, message = "error", "Prowlarr paused it after errors; it tries again by itself."
        row = {"id": it["id"], "name": it.get("name", ""), "kind": kind, "status": status, "message": message,
               "preset": mine.get("preset") or (preset_for_url(field(it, "baseUrl") or "") if kind == "usenet" else
                                                next((p["id"] for p in TORRENT_INDEXERS if p["definition"] == (it.get("definitionName") or "").lower()), ""))}
        if kind == "torrent":
            row["public"] = it.get("privacy") == "public"
        out.append(row)
    return out


def subtitles_view():
    v = {"installed": "bazarr" in SERVICES, "languages": [], "opensubtitles": {"configured": False, "username": ""}}
    if not v["installed"]:
        return v
    try:
        langs = ok(*bazarr("GET", "/system/languages", timeout=8), "Bazarr")
        settings = ok(*bazarr("GET", "/system/settings", timeout=8), "Bazarr")
    except Down:
        return v
    v["languages"] = sorted(x["code2"] for x in langs if x.get("enabled"))
    user = (settings.get("opensubtitlescom") or {}).get("username") or ""
    on = "opensubtitlescom" in ((settings.get("general") or {}).get("enabled_providers") or [])
    v["opensubtitles"] = {"configured": bool(on and user), "username": user if on else ""}
    return v


def view():
    st = state()
    usenet = usenet_view(st)
    indexers = indexers_view(st)
    torrents = torrents_view(st)
    good = {k: any(i["status"] == "ok" and i["kind"] == k for i in indexers) for k in ("usenet", "torrent")}
    services = [{"type": t, "ready": service_ready(t)} for t in SERVICES]
    if QB_URL:
        services.append({"type": "qbittorrent", "ready": torrents["status"] == "ok"})
    return {
        "installed": bool(CONFIG["installed"]) and bool(SERVICES),
        "ready": (usenet["status"] == "ok" and good["usenet"]) or (torrents["enabled"] and torrents["status"] == "ok" and good["torrent"]),
        "services": services,
        "usenet": usenet,
        "indexers": indexers,
        "torrents": torrents,
        "subtitles": subtitles_view(),
        "presets": {"providers": PROVIDERS, "indexers": indexer_presets()},
    }


def indexer_presets():
    out = [dict({k: p[k] for k in ("id", "name", "url", "signup")}, kind="usenet", needs=["api_key"]) for p in INDEXERS]
    if QB_URL:
        out += [dict({k: p[k] for k in ("id", "name", "url", "signup", "for")}, kind="torrent", public=True, needs=[]) for p in TORRENT_INDEXERS]
        out.append(PRIVATE_TRACKER)
    return out


# ---- Usenet (SABnzbd) ----

SAB_PLAIN = [
    (r"(?i)authentication failed|wrong username|bad username|invalid user|password", "The provider didn't accept this username and password."),
    (r"(?i)name or service not known|getaddrinfo|nodename|no address|is not valid", "There's no server at this address. Check the host name."),
    (r"(?i)timed? ?out", "The server didn't answer in time. Check the host and port (563 with SSL, 119 without)."),
    (r"(?i)refused", "The server refused the connection. Check the port (563 with SSL, 119 without)."),
    (r"(?i)ssl|certificate|tls", "The secure connection failed. Check the port and the SSL switch."),
    (r"(?i)too many connections|max.*connections", "The provider allows fewer connections. Lower the number."),
]


def plain(msg, table):
    for pat, words in table:
        if re.search(pat, msg or ""):
            return words + " (" + re.sub(r"<[^>]+>", "", msg).strip()[:160] + ")"
    return re.sub(r"<[^>]+>", "", msg or "").strip()[:200] or "The test failed."


def put_usenet(b):
    host = str(b.get("host") or "").strip()
    if not HOST.match(host):
        raise Problem("Type the provider's server address, like news.example.com.")
    try:
        port = int(b.get("port") or (563 if b.get("ssl", True) else 119))
        connections = int(b.get("connections") or 20)
    except (TypeError, ValueError):
        raise Problem("port and connections must be numbers")
    if not 0 < port < 65536:
        raise Problem("The port is a number from 1 to 65535 (usually 563).")
    if not 0 < connections <= 200:
        raise Problem("Connections must be between 1 and 200.")
    ssl = bool(b.get("ssl", True))
    username = str(b.get("username") or "").strip()
    password = b.get("password")
    servers = sab_servers()
    current = next((x for x in servers if x.get("name") == SERVER_NAME), servers[0] if servers else None)
    name = current["name"] if current else SERVER_NAME
    if password is None and not current:
        raise Problem("Type the password for your Usenet account.")
    params = {"mode": "set_config", "section": "servers", "keyword": name, "host": host, "port": port, "ssl": int(ssl),
              "ssl_verify": 3 if ssl else 0, "username": username, "connections": connections, "enable": 1,
              "displayname": str(b.get("name") or next((p["name"] for p in PROVIDERS if p["host"] == host), host))[:80]}
    if password is not None:
        params["password"] = str(password)
    sab(params)
    # Other servers SABnzbd may have had (it uses all of them): only the one set here.
    for other in servers:
        if other.get("name") != name:
            sab({"mode": "del_config", "section": "servers", "keyword": other["name"]})
    test = {"mode": "config", "name": "test_server", "host": host, "port": port, "ssl": int(ssl), "ssl_verify": 3 if ssl else 0,
            "username": username, "password": str(password) if password is not None else "*****", "server": name,
            "connections": connections, "timeout": 15}
    try:
        res = sab(test, timeout=60).get("value", {})
        good, msg = bool(res.get("result")), str(res.get("message") or "")
    except Down as e:
        good, msg = False, str(e)
    st = state()
    st["usenet"] = {"host": host, "username": username, "port": port, "status": "ok" if good else "error",
                    "message": "" if good else plain(msg, SAB_PLAIN), "at": int(time.time())}
    save_state(st)
    log("usenet:", host, port, "ok" if good else "error: " + msg[:120])
    return view()


def delete_usenet():
    for s in sab_servers():
        sab({"mode": "del_config", "section": "servers", "keyword": s["name"]})
    st = state()
    st.pop("usenet", None)
    save_state(st)
    log("usenet: removed")
    return view()


# ---- indexers (Prowlarr) ----

PROWLARR_PLAIN = [
    (r"(?i)invalid username|username/password|password combination|login failed|wrong password", "The tracker didn't accept this username and password."),
    (r"(?i)api ?key|unauthori[sz]ed|\b401\b|\b403\b|incorrect user credentials|apikey", "The indexer didn't accept this API key."),
    (r"(?i)name or service not known|no such host|nodename|resolve", "There's no indexer at this address. Check the URL."),
    (r"(?i)timed? ?out", "The indexer didn't answer in time. Try again later."),
    (r"(?i)ssl|certificate|tls", "The secure connection to the indexer failed. Check the URL."),
    (r"(?i)request limit|too many|\b429\b", "The indexer's daily limit is used up; it works again tomorrow."),
]


def failure_text(out):
    if isinstance(out, list):
        msgs = [str(x.get("errorMessage") or "") for x in out if isinstance(x, dict)]
        msg = "; ".join(m for m in msgs if m)
    elif isinstance(out, dict):
        msg = str(out.get("message") or out.get("errorMessage") or out)
    else:
        msg = str(out)
    msg = msg.replace(", check the log above for more details", "").replace("check the log for more details", "")
    msg = re.sub(r"(?i),? *check the log above the ValidationFailure for more details\.? *(Error: *)*", ": ", msg).strip(": ")
    return plain(msg, PROWLARR_PLAIN)


_schema = {"items": None}


def full_schema():
    """Prowlarr's indexer types. Its schema is large and slow at first (it fetches its indexer
    definitions), so it is read once, in the background at start, and kept."""
    if _schema["items"] is None:
        _schema["items"] = ok(*prowlarr("GET", "/indexer/schema", timeout=180), "Prowlarr")
    return _schema["items"]


def newznab_schema():
    return [json.loads(json.dumps(s)) for s in full_schema() if s.get("implementation") == "Newznab"]


def definition_item(name):
    n = name.strip().lower()
    for s in full_schema():
        if (s.get("definitionName") or "").lower() == n or (s.get("name") or "").lower() == n:
            return json.loads(json.dumps(s))
    return None


KEY_FIELDS = ("apikey", "apiKey", "passkey", "rsskey", "key", "token")


def needs_of(item):
    names = {f.get("name") for f in item.get("fields", [])}
    out = [n for n in ("username", "password") if n in names]
    if names & set(KEY_FIELDS):
        out.append("api_key")
    return out


def warm_schema():
    for _ in range(60):
        try:
            full_schema()
            log("prowlarr: %d indexer types" % len(_schema["items"]))
            return
        except (Down, Problem, KeyError, TypeError) as e:
            log("prowlarr schema not yet:", e)
            time.sleep(30)


def add_indexer(b):
    tpreset = next((p for p in TORRENT_INDEXERS if p["id"] == b.get("preset")), None)
    if b.get("kind") == "torrent" or tpreset or b.get("definition"):
        return add_torrent_indexer(b, tpreset)
    preset = next((p for p in INDEXERS if p["id"] == b.get("preset")), None)
    if b.get("preset") and not preset:
        raise Problem("Unknown preset " + str(b.get("preset"))[:40])
    url = str(b.get("url") or (preset or {}).get("url") or "").strip().rstrip("/")
    u = urllib.parse.urlparse(url)
    if u.scheme not in ("http", "https") or not u.netloc:
        raise Problem("Type the indexer's address, like https://api.example.com.")
    api_key = str(b.get("api_key") or "").strip()
    if not api_key:
        raise Problem("Type the indexer's API key (on its site, under your profile or API).")
    name = str(b.get("name") or (preset or {}).get("name") or u.netloc).strip()[:60]
    newznab = newznab_schema()
    item = None
    if preset:
        item = next((s for s in newznab if s.get("name") == preset["definition"]), None)
    item = item or next((s for s in newznab if s.get("name") == "Generic Newznab"), None) or (newznab[0] if newznab else None)
    if not item:
        raise Down("Prowlarr has no Newznab indexer type")
    for f in item.get("fields", []):
        if f.get("name") == "baseUrl":
            f["value"] = url
        elif f.get("name") == "apiKey":
            f["value"] = api_key
        elif f.get("name") == "apiPath" and not f.get("value"):
            f["value"] = "/api"
    # The same indexer again (a new key, say): replace it rather than add a twin.
    existing = next((x for x in ok(*prowlarr("GET", "/indexer"), "Prowlarr")
                     if x.get("protocol") == "usenet" and (field(x, "baseUrl") or "").rstrip("/").lower() == url.lower()), None)
    # Usenet first: Radarr, Sonarr and Lidarr prefer lower numbers.
    return save_indexer(item, name, existing, 25, (preset or {}).get("id", "") or preset_for_url(url), url)


def add_torrent_indexer(b, preset):
    definition = (preset or {}).get("definition") or str(b.get("definition") or b.get("preset") or "").strip()
    if (not definition or definition == "private") and b.get("url") and not b.get("definition"):
        return add_torznab(b)
    if not definition or definition == "private":
        raise Problem("Pick a torrent site, or type Prowlarr's name for your private tracker (like torrentleech).")
    item = definition_item(definition)
    if not item or item.get("protocol") != "torrent":
        raise Problem("Prowlarr has no torrent site called " + definition[:60] + ".")
    values = {"username": str(b.get("username") or "").strip(), "password": str(b.get("password") or "")}
    api_key = str(b.get("api_key") or "").strip()
    url = str(b.get("url") or "").strip().rstrip("/")
    names = {f.get("name") for f in item.get("fields", [])}
    if item.get("privacy") != "public":
        missing = [n for n in needs_of(item) if (n == "api_key" and not api_key) or (n != "api_key" and not values[n])]
        if missing:
            raise Problem("%s needs your %s." % (item.get("name", definition), " and ".join(m.replace("api_key", "API key or passkey") for m in missing)))
    for f in item.get("fields", []):
        n = f.get("name")
        if n in values and values[n]:
            f["value"] = values[n]
        elif n in KEY_FIELDS and api_key:
            f["value"] = api_key
        elif n == "baseUrl" and url:
            f["value"] = url if url in (item.get("indexerUrls") or [url]) else f.get("value")
    if url and "baseUrl" not in names:
        log("indexer: %s has no address to set" % definition)
    name = str(b.get("name") or (preset or {}).get("name") or item.get("name") or definition).strip()[:60]
    existing = next((x for x in ok(*prowlarr("GET", "/indexer"), "Prowlarr")
                     if (x.get("definitionName") or "").lower() == (item.get("definitionName") or "").lower()), None)
    return save_indexer(item, name, existing, 35, (preset or {}).get("id", "") or ("private" if item.get("privacy") != "public" else ""), definition)


def add_torznab(b):
    """Another torrent indexer by its Torznab address (Jackett, a tracker's own Torznab feed…)."""
    url = str(b.get("url") or "").strip().rstrip("/")
    u = urllib.parse.urlparse(url)
    if u.scheme not in ("http", "https") or not u.netloc:
        raise Problem("Type the indexer's Torznab address, like https://tracker.example/api.")
    item = next((s for s in full_schema() if s.get("implementation") == "Torznab" and s.get("name") == "Generic Torznab"), None) \
        or next((s for s in full_schema() if s.get("implementation") == "Torznab"), None)
    if not item:
        raise Down("Prowlarr has no Torznab indexer type")
    item = json.loads(json.dumps(item))
    path = u.path if u.path not in ("", "/") else "/api"
    base = "%s://%s" % (u.scheme, u.netloc)
    for f in item.get("fields", []):
        if f.get("name") == "baseUrl":
            f["value"] = base
        elif f.get("name") == "apiPath":
            f["value"] = path
        elif f.get("name") == "apiKey":
            f["value"] = str(b.get("api_key") or "").strip()
    name = str(b.get("name") or u.netloc).strip()[:60]
    existing = next((x for x in ok(*prowlarr("GET", "/indexer"), "Prowlarr")
                     if x.get("protocol") == "torrent" and (field(x, "baseUrl") or "").rstrip("/").lower() == base.lower()), None)
    return save_indexer(item, name, existing, 35, "", base + path)


def save_indexer(item, name, existing, priority, preset_id, label):
    """Test it in Prowlarr, then save it; one that fails the test is kept switched off."""
    profiles = ok(*prowlarr("GET", "/appprofile"), "Prowlarr")
    item.update({"name": name, "enable": True, "appProfileId": profiles[0]["id"] if profiles else 1, "priority": priority})
    item.pop("id", None)
    if existing:
        item["id"] = existing["id"]
    code, out = prowlarr("POST", "/indexer/test", item, timeout=90)
    good = code < 300
    message = "" if good else failure_text(out)
    item["enable"] = good  # a failing one is kept switched off, so Radarr and Sonarr don't get it
    if existing:
        code, out = prowlarr("PUT", "/indexer/%d?forceSave=true" % existing["id"], item, timeout=60)
    else:
        code, out = prowlarr("POST", "/indexer?forceSave=true", item, timeout=60)
    if code >= 300 or not isinstance(out, dict):
        raise Down("Prowlarr didn't save the indexer: " + failure_text(out))
    st = state()
    entry = {"preset": preset_id, "status": "ok" if good else "error", "message": message, "at": int(time.time())}
    st.setdefault("indexers", {})[str(out["id"])] = entry
    save_state(st)
    log("indexer:", name, label, "ok" if good else "error: " + message[:120])
    return view()


def delete_indexer(iid):
    if prowlarr("GET", "/indexer/%d" % iid)[0] == 404:
        raise LookupError("no such indexer")
    ok(*prowlarr("DELETE", "/indexer/%d" % iid), "Prowlarr")
    st = state()
    st.get("indexers", {}).pop(str(iid), None)
    save_state(st)
    log("indexer removed:", iid)
    return view()


# ---- torrents (qBittorrent) ----

API = {"radarr": "/api/v3", "sonarr": "/api/v3", "lidarr": "/api/v1", "prowlarr": "/api/v1"}


def arr(t, method, path, body=None, timeout=20):
    return http(method, SERVICES[t] + API[t] + path, body, {"X-Api-Key": keys()[t]}, timeout=timeout)


def run(*cmd, check=True, timeout=60):
    return subprocess.run([str(c) for c in cmd], check=check, capture_output=True, text=True, timeout=timeout)


def torrents_on():
    return bool(MARKER) and os.path.exists(MARKER)


def qb_login(timeout=8):
    """A qBittorrent session (its SID cookie) with the box's login."""
    data = urllib.parse.urlencode({"username": ADMIN, "password": keys()["qbittorrent"]}).encode()
    req = urllib.request.Request(QB_URL + "/api/v2/auth/login", data=data, method="POST", headers={"Referer": QB_URL})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            r.read()
            cookie = r.headers.get("Set-Cookie") or ""
    except urllib.error.HTTPError as e:
        raise Down("qBittorrent didn't take the box's login" if e.code in (401, 403) else "qBittorrent answered %s" % e.code)
    except (urllib.error.URLError, OSError) as e:
        raise Down("qBittorrent isn't answering (%s)" % str(getattr(e, "reason", e))[:80])
    # qBittorrent 5 names the cookie QBT_SID_<port> (older ones SID) and answers 204 on success.
    m = re.search(r"((?:QBT_)?SID(?:_\d+)?)=([^;]+)", cookie)
    if not m:
        raise Down("qBittorrent didn't take the box's login")
    return m.group(1) + "=" + m.group(2)


def qb(sid, path, form=None, timeout=20):
    data = urllib.parse.urlencode(form).encode() if form is not None else None
    req = urllib.request.Request(QB_URL + "/api/v2" + path, data=data, method="POST" if form is not None else "GET",
                                 headers={"Cookie": sid, "Referer": QB_URL})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        raise Down("qBittorrent %s: %s %s" % (path, e.code, e.read()[:120].decode(errors="replace")))
    except (urllib.error.URLError, OSError) as e:
        raise Down("qBittorrent isn't answering (%s)" % str(getattr(e, "reason", e))[:80])
    try:
        return json.loads(raw) if raw.strip() else None
    except ValueError:
        return raw.decode(errors="replace")


def seeding(st):
    return dict(SEEDING, **(st.get("seeding") or {}))


def apply_qb(st, wait=60):
    """The box's settings in qBittorrent: folders and categories, seeding limits, the VPN interface."""
    end = time.time() + wait
    while True:
        try:
            sid = qb_login()
            break
        except Down:
            if time.time() > end:
                raise
            time.sleep(2)
    sd = seeding(st)
    root = CONFIG["torrent_dir"]
    prefs = {
        "save_path": root + "/complete", "temp_path_enabled": True, "temp_path": root + "/incomplete",
        "auto_tmm_enabled": True, "torrent_changed_tmm_enabled": True, "save_path_changed_tmm_enabled": True, "category_changed_tmm_enabled": True,
        "upnp": False, "web_ui_upnp": False,
        # Stop (not remove) at the limit: Radarr, Sonarr and Lidarr remove it themselves once it stopped.
        "max_ratio_enabled": sd["ratio"] > 0, "max_ratio": sd["ratio"] if sd["ratio"] > 0 else -1,
        "max_seeding_time_enabled": sd["days"] > 0, "max_seeding_time": int(sd["days"] * 1440) if sd["days"] > 0 else -1,
        "max_ratio_act": 0,
        "current_network_interface": IFACE if os.path.exists(VPN_CONF) else "",
    }
    qb(sid, "/app/setPreferences", {"json": json.dumps(prefs)})
    have = qb(sid, "/torrents/categories") or {}
    for c in CATEGORIES:
        qb(sid, "/torrents/editCategory" if c in have else "/torrents/createCategory", {"category": c, "savePath": root + "/complete/" + c})
    return qb(sid, "/app/version")


def set_clients(on):
    """qBittorrent in Radarr, Sonarr, Lidarr and Prowlarr: on or off with torrents."""
    missing = []
    for t in ("radarr", "sonarr", "lidarr", "prowlarr"):
        if t not in SERVICES:
            continue
        clients = [c for c in ok(*arr(t, "GET", "/downloadclient"), t) if c.get("implementation") == "QBittorrent"]
        if not clients:
            missing.append(t)
        for c in clients:
            if bool(c.get("enable")) != on:
                c["enable"] = on
                ok(*arr(t, "PUT", "/downloadclient/%d?forceSave=true" % c["id"], c, timeout=60), t)
    return missing


def torrents_view(st):
    v = {"enabled": torrents_on(), "status": "off", "message": "", "seeding": seeding(st), "vpn": vpn_view(st)}
    if not QB_URL:
        v["message"] = "qBittorrent isn't on this box."
        return v
    if v["enabled"]:
        try:
            qb_login(timeout=5)
            v["status"] = "ok"
        except Down as e:
            v.update(status="error", message=str(e) + ".")
        last = st.get("torrents") or {}
        if v["status"] == "ok" and last.get("status") == "error":
            v.update(status="error", message=last.get("message", ""))
        if v["status"] == "ok" and v["vpn"]["status"] == "down":
            v.update(status="error", message="The VPN is down, so torrents can't reach the internet (on purpose).")
    return v


def put_torrents(b):
    if not QB_URL:
        raise Problem("qBittorrent isn't on this box.")
    if not isinstance(b.get("enabled"), bool):
        raise Problem("enabled must be true or false")
    st = state()
    if b.get("seeding") is not None:
        sd = b["seeding"]
        try:
            ratio, days = float(sd.get("ratio", SEEDING["ratio"])), float(sd.get("days", SEEDING["days"]))
        except (AttributeError, TypeError, ValueError):
            raise Problem("seeding is {ratio, days} with numbers")
        if not (0 <= ratio <= 100 and 0 <= days <= 365):
            raise Problem("Seed up to a ratio between 0 and 100 and for 0 to 365 days (0 = no limit).")
        st["seeding"] = {"ratio": round(ratio, 2), "days": days if days % 1 else int(days)}
    if b["enabled"]:
        with open(MARKER, "w"):
            pass
        st["torrents"] = {"status": "ok", "message": ""}
        try:
            r = run(T["systemctl"], "start", "qbittorrent.service", check=False, timeout=120)
            if r.returncode != 0:
                raise Down("qBittorrent didn't start: " + (r.stderr or r.stdout).strip()[-160:])
            version = apply_qb(st)
            missing = set_clients(True)
            if missing:
                st["torrents"] = {"status": "error", "message": "qBittorrent isn't connected to " + ", ".join(missing) + " yet; restart the box once."}
            log("torrents: on, qBittorrent", version)
        except Down as e:
            st["torrents"] = {"status": "error", "message": str(e)}
            log("torrents: on, but", e)
    else:
        set_clients(False)
        run(T["systemctl"], "stop", "qbittorrent.service", check=False, timeout=300)
        if os.path.exists(MARKER):
            os.remove(MARKER)
        st["torrents"] = {"status": "off", "message": ""}
        log("torrents: off")
    save_state(st)
    return view()


# ---- the VPN for torrents (WireGuard) ----

WG_KEY = re.compile(r"^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$")
ENDPOINT = re.compile(r"^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+):(\d{1,5})$")


def parse_wg(text):
    """A wg-quick config: [Interface] PrivateKey, Address, DNS?, MTU?; one [Peer] PublicKey, Endpoint,
    AllowedIPs?, PresharedKey?, PersistentKeepalive?. Scripts (PostUp…) are not run."""
    iface, peers, cur = {}, [], None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.lower() == "[interface]":
            cur = iface
            continue
        if line.lower() == "[peer]":
            cur = {}
            peers.append(cur)
            continue
        if "=" not in line or cur is None:
            raise Problem("This doesn't look like a WireGuard config (a line outside [Interface] or [Peer]: %s)." % line[:40])
        k, v = (x.strip() for x in line.split("=", 1))
        cur[k.lower()] = (cur[k.lower()] + "," + v) if k.lower() in cur and k.lower() in ("address", "dns", "allowedips") else v
    if not WG_KEY.match(iface.get("privatekey", "")):
        raise Problem("The config has no valid PrivateKey under [Interface].")
    addrs = [a.strip() for a in iface.get("address", "").split(",") if a.strip()]
    if not addrs:
        raise Problem("The config has no Address under [Interface].")
    for a in addrs:
        try:
            socket.inet_pton(socket.AF_INET6 if ":" in a else socket.AF_INET, a.split("/")[0])
        except OSError:
            raise Problem("The Address %s isn't an IP address." % a[:40])
    if len(peers) != 1:
        raise Problem("The config needs exactly one [Peer] (the VPN server).")
    peer = peers[0]
    if not WG_KEY.match(peer.get("publickey", "")):
        raise Problem("The [Peer] has no valid PublicKey.")
    if peer.get("presharedkey") and not WG_KEY.match(peer["presharedkey"]):
        raise Problem("The [Peer]'s PresharedKey isn't valid.")
    if not ENDPOINT.match(peer.get("endpoint", "")):
        raise Problem("The [Peer] needs an Endpoint like vpn.example.com:51820.")
    dns = []
    for d in iface.get("dns", "").split(","):
        d = d.strip()
        try:
            socket.inet_pton(socket.AF_INET6 if ":" in d else socket.AF_INET, d)
            dns.append(d)
        except OSError:
            pass
    mtu = iface.get("mtu", "1420")
    if not mtu.isdigit() or not 1280 <= int(mtu) <= 9000:
        raise Problem("MTU must be a number from 1280 to 9000.")
    return {"private_key": iface["privatekey"], "addresses": addrs, "dns": dns, "mtu": mtu,
            "public_key": peer["publickey"], "preshared_key": peer.get("presharedkey", ""), "endpoint": peer["endpoint"],
            "allowed_ips": peer.get("allowedips", "0.0.0.0/0, ::/0"), "keepalive": peer.get("persistentkeepalive", "25")}


def read_vpn():
    try:
        with open(VPN_CONF) as f:
            return parse_wg(f.read())
    except FileNotFoundError:
        return None
    except Problem as e:
        log("vpn config:", e)
        return None


def apply_vpn():
    """pocket-box-vpn: the kill switch and the tunnel from the saved config, or nothing without one."""
    run(T["ip"], "link", "del", IFACE, check=False)
    for fam in ("-4", "-6"):
        for _ in range(10):
            if run(T["ip"], fam, "rule", "del", "priority", RULE_PRIORITY, check=False).returncode != 0:
                break
        run(T["ip"], fam, "route", "flush", "table", TABLE, check=False)
    c = read_vpn()
    if not c:
        if os.path.exists(VPN_RESOLV):
            os.remove(VPN_RESOLV)
        log("vpn: none")
        return
    uid = pwd.getpwnam(CONFIG["qbittorrent_user"]).pw_uid
    # First the way out that isn't one: whatever qBittorrent's user sends goes by this table, and the
    # table ends in unreachable, so nothing leaves while the tunnel is down.
    for fam in ("-4", "-6"):
        run(T["ip"], fam, "route", "replace", "unreachable", "default", "metric", "4096", "table", TABLE, check=fam == "-4")
        run(T["ip"], fam, "rule", "add", "priority", RULE_PRIORITY, "uidrange", "%d-%d" % (uid, uid), "lookup", TABLE, check=fam == "-4")
    with open(VPN_RESOLV + ".tmp", "w") as f:
        f.write("".join("nameserver %s\n" % d for d in (c["dns"] or ["1.1.1.1", "9.9.9.9"])))
    os.chmod(VPN_RESOLV + ".tmp", 0o644)
    os.replace(VPN_RESOLV + ".tmp", VPN_RESOLV)
    wgconf = os.path.join(VPN_DIR, "wg-setconf.conf")
    try:
        with open(os.open(wgconf, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
            f.write("[Interface]\nPrivateKey = %s\n\n[Peer]\nPublicKey = %s\nEndpoint = %s\nAllowedIPs = %s\nPersistentKeepalive = %s\n%s" % (
                c["private_key"], c["public_key"], c["endpoint"], c["allowed_ips"], c["keepalive"],
                ("PresharedKey = %s\n" % c["preshared_key"]) if c["preshared_key"] else ""))
        run(T["ip"], "link", "add", IFACE, "type", "wireguard")
        run(T["wg"], "setconf", IFACE, wgconf)
        for a in c["addresses"]:
            run(T["ip"], "-6" if ":" in a else "-4", "address", "add", a, "dev", IFACE)
        run(T["ip"], "link", "set", "dev", IFACE, "mtu", c["mtu"], "up")
        for fam in ("-4", "-6"):
            if any((":" in a) == (fam == "-6") for a in c["addresses"]):
                run(T["ip"], fam, "route", "replace", "default", "dev", IFACE, "table", TABLE)
        log("vpn: tunnel set up to", c["endpoint"])
    except subprocess.CalledProcessError as e:
        # The kill switch above stays: qBittorrent simply has no way out.
        log("vpn: tunnel not up:", (e.stderr or e.stdout or str(e)).strip()[:200])
    finally:
        if os.path.exists(wgconf):
            os.remove(wgconf)


def handshake_age():
    r = run(T["wg"], "show", IFACE, "latest-handshakes", check=False)
    if r.returncode != 0:
        return None
    stamps = [int(x.split()[-1]) for x in r.stdout.splitlines() if x.split() and x.split()[-1].isdigit()]
    return (time.time() - max(stamps)) if stamps and max(stamps) > 0 else None


def public_ip(as_qbittorrent):
    """What the internet sees: the box's own address, or (as qBittorrent's user) the tunnel's."""
    host = "api.ipify.org"
    try:
        ip = socket.getaddrinfo(host, 443, socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
    except OSError:
        return None
    cmd = [T["curl"], "-s", "-4", "-m", "15", "--resolve", "%s:443:%s" % (host, ip), "https://" + host]
    if as_qbittorrent:
        u = pwd.getpwnam(CONFIG["qbittorrent_user"])
        cmd = [T["setpriv"], "--reuid=%d" % u.pw_uid, "--regid=%d" % u.pw_gid, "--clear-groups"] + cmd
    r = run(*cmd, check=False, timeout=30)
    out = r.stdout.strip()
    return out if r.returncode == 0 and re.match(r"^[0-9.]+$", out) else None


def vpn_view(st):
    c = read_vpn() if VPN_DIR else None
    if not c:
        return {"configured": False, "status": "none", "message": "", "endpoint": ""}
    age = handshake_age()
    last = st.get("vpn") or {}
    if age is not None and age < 300:
        return {"configured": True, "status": "up", "message": "", "endpoint": c["endpoint"]}
    msg = last.get("message") if last.get("status") == "down" else ""
    return {"configured": True, "status": "down", "endpoint": c["endpoint"],
            "message": msg or "The VPN isn't answering (no handshake with %s). Torrents can't reach the internet until it does." % c["endpoint"]}


def restart_qb(st):
    if torrents_on():
        run(T["systemctl"], "restart", "qbittorrent.service", check=False, timeout=300)
        try:
            apply_qb(st)
        except Down as e:
            log("torrents after a VPN change:", e)


def put_vpn(b):
    if not QB_URL:
        raise Problem("qBittorrent isn't on this box.")
    text = b.get("wireguard")
    if not isinstance(text, str) or not text.strip():
        raise Problem("Paste the WireGuard config from your VPN provider (a .conf file).")
    if len(text) > 8000:
        raise Problem("That's too long for a WireGuard config.")
    c = parse_wg(text)
    os.makedirs(VPN_DIR, mode=0o700, exist_ok=True)
    with open(os.open(VPN_CONF + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        f.write(text)
    os.replace(VPN_CONF + ".tmp", VPN_CONF)
    run(T["systemctl"], "restart", "pocket-box-vpn.service", check=False, timeout=120)
    st = state()
    status, message = "down", ""
    for _ in range(20):
        if handshake_age() is not None:
            break
        time.sleep(1)
    if handshake_age() is None:
        message = "The VPN didn't answer (no handshake with %s within 20 seconds). Check the config, or get a new one from your VPN provider." % c["endpoint"]
    else:
        home, tunnel = public_ip(False), public_ip(True)
        if not tunnel:
            message = "The tunnel is up, but nothing gets through it to the internet. Check the config's Address and DNS."
        elif home and tunnel == home:
            message = "Traffic through the VPN still shows the home address (%s)." % home
        else:
            status = "up"
    st["vpn"] = {"status": status, "message": message, "at": int(time.time())}
    save_state(st)
    log("vpn:", c["endpoint"], status, message[:120])
    restart_qb(st)
    return view()


def delete_vpn():
    for p in (VPN_CONF, VPN_RESOLV):
        if os.path.exists(p):
            os.remove(p)
    run(T["systemctl"], "restart", "pocket-box-vpn.service", check=False, timeout=120)
    st = state()
    st.pop("vpn", None)
    save_state(st)
    log("vpn: removed")
    restart_qb(st)
    return view()


# ---- subtitles (Bazarr) ----

def put_subtitles(b):
    langs = b.get("languages")
    if not isinstance(langs, list) or not langs or not all(isinstance(x, str) and LANG.match(x.lower()) for x in langs):
        raise Problem("Pick at least one subtitle language (two-letter codes like en, sr).")
    langs = list(dict.fromkeys(x.lower() for x in langs))
    known = {x["code2"] for x in ok(*bazarr("GET", "/system/languages"), "Bazarr")}
    unknown = [x for x in langs if x not in known]
    if unknown:
        raise Problem("Bazarr doesn't know the language " + ", ".join(unknown) + ".")
    settings = ok(*bazarr("GET", "/system/settings"), "Bazarr")
    profiles = ok(*bazarr("GET", "/system/languages/profiles"), "Bazarr") or []
    mine = next((p for p in profiles if p.get("name") == PROFILE_NAME), None)
    pid = mine["profileId"] if mine else max([p["profileId"] for p in profiles] + [0]) + 1
    profile = {"profileId": pid, "name": PROFILE_NAME, "cutoff": None, "mustContain": [], "mustNotContain": [], "originalFormat": None, "tag": None,
               "items": [{"id": i + 1, "language": c, "audio_exclude": "False", "audio_only_include": "False", "hi": "False", "forced": "False"}
                         for i, c in enumerate(langs)]}
    others = [{k: p.get(k) for k in ("profileId", "name", "cutoff", "items", "mustContain", "mustNotContain", "originalFormat", "tag")}
              for p in profiles if p.get("profileId") != pid]
    # Bazarr's own languages: what any profile uses.
    enabled = list(dict.fromkeys(langs + [i["language"] for p in others for i in p.get("items", [])]))
    form = [("languages-enabled", c) for c in enabled] + [
        ("languages-profiles", json.dumps(others + [profile])),
        ("settings-general-serie_default_enabled", "true"), ("settings-general-serie_default_profile", str(pid)),
        ("settings-general-movie_default_enabled", "true"), ("settings-general-movie_default_profile", str(pid))]
    os_in = b.get("opensubtitles")
    if os_in is not None:
        if not isinstance(os_in, dict):
            raise Problem("opensubtitles is {username, password}")
        providers = [p for p in ((settings.get("general") or {}).get("enabled_providers") or []) if p != "opensubtitlescom"]
        user = str(os_in.get("username") or "").strip()
        pw = os_in.get("password")
        if user:
            had = (settings.get("opensubtitlescom") or {}).get("username")
            if not pw and had != user:
                raise Problem("Type the password for your OpenSubtitles.com account.")
            providers.append("opensubtitlescom")
            form.append(("settings-opensubtitlescom-username", user))
            if pw:
                form.append(("settings-opensubtitlescom-password", str(pw)))
        form += [("settings-general-enabled_providers", p) for p in providers] or [("settings-general-enabled_providers", "")]
    ok(*bazarr("POST", "/system/settings", form=form, timeout=60), "Bazarr")
    log("subtitles:", ",".join(langs), "opensubtitles:", "unchanged" if os_in is None else ("on" if (os_in or {}).get("username") else "off"))
    return view()


# ---- HTTP ----

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(self.command, self.path.split("?")[0], fmt % args, flush=True)

    def reply(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > 16 << 10:
            raise Problem("request too large")
        try:
            b = json.loads(self.rfile.read(n) or b"{}") if n else {}
        except ValueError:
            raise Problem("not JSON")
        if not isinstance(b, dict):
            raise Problem("not a JSON object")
        return b

    def route(self):
        m, p = self.command, self.path.split("?")[0].rstrip("/")
        if p == "/v1/downloads" and m == "GET":
            return view()
        if not CONFIG["installed"] or not SERVICES:
            raise LookupError("Downloads aren't on this box (no Pocket Watch, Requests or Subtitles).")
        with lock:
            if p == "/v1/downloads/usenet" and m == "PUT":
                return put_usenet(self.body())
            if p == "/v1/downloads/usenet" and m == "DELETE":
                return delete_usenet()
            if p == "/v1/downloads/indexers" and m == "POST":
                return add_indexer(self.body())
            mi = re.fullmatch(r"/v1/downloads/indexers/(\d+)", p)
            if mi and m == "DELETE":
                return delete_indexer(int(mi.group(1)))
            if p == "/v1/downloads/subtitles" and m == "PUT":
                return put_subtitles(self.body())
            if p == "/v1/downloads/torrents" and m == "PUT":
                return put_torrents(self.body())
            if p == "/v1/downloads/vpn" and m == "PUT":
                return put_vpn(self.body())
            if p == "/v1/downloads/vpn" and m == "DELETE":
                return delete_vpn()
        raise LookupError("not found")

    def dispatch(self):
        try:
            self.reply(200, self.route())
        except Problem as e:
            self.reply(400, {"error": str(e)})
        except LookupError as e:
            self.reply(404, {"error": str(e)})
        except Down as e:
            log("error:", e)
            self.reply(502, {"error": "A download service isn't answering: " + str(e)[:200]})
        except (KeyError, IndexError, TypeError, ValueError, OSError, subprocess.SubprocessError) as e:
            log("error:", repr(e))
            self.reply(500, {"error": "Something went wrong on the box: " + str(e)[:200]})

    do_GET = do_PUT = do_POST = do_DELETE = dispatch


class UnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def get_request(self):
        conn, _ = super().get_request()
        return conn, ("core", 0)


def main():
    os.makedirs(CONFIG["state_dir"], mode=0o700, exist_ok=True)
    sock = CONFIG["socket"]
    if os.path.exists(sock):
        os.remove(sock)
    server = UnixServer(sock, Handler)
    import grp
    os.chown(sock, 0, grp.getgrnam(CONFIG["group"]).gr_gid)
    os.chmod(sock, 0o660)
    if "prowlarr" in SERVICES:
        threading.Thread(target=warm_schema, daemon=True).start()
    log("listening on", sock, "for", ", ".join(SERVICES) or "nothing (no download services on this box)")
    server.serve_forever()


if __name__ == "__main__":
    if sys.argv[2:] == ["vpn"]:
        apply_vpn()
    else:
        main()
