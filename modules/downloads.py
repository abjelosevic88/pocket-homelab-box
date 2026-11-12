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

Every change answers with the GET body. A failed test still answers 200, with status "error" and a
message in plain words; 400 is for bad input only. Passwords and API keys are never sent back.
"""
import json
import os
import re
import socketserver
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler

CONFIG = json.load(open(sys.argv[1]))
SERVICES = CONFIG["services"]  # type → http://127.0.0.1:<port>, only those on this box
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
        if it.get("protocol") != "usenet":
            continue
        mine = known.get(str(it["id"]), {})
        status, message = mine.get("status", "ok"), mine.get("message", "")
        s = statuses.get(it["id"])
        if not it.get("enable"):
            status, message = "error", message or "Switched off in Prowlarr."
        elif s and s.get("disabledTill") and status == "ok":
            status, message = "error", "Prowlarr paused it after errors; it tries again by itself."
        out.append({"id": it["id"], "name": it.get("name", ""), "preset": mine.get("preset") or preset_for_url(field(it, "baseUrl") or ""),
                    "status": status, "message": message})
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
    return {
        "installed": bool(CONFIG["installed"]) and bool(SERVICES),
        "ready": usenet["status"] == "ok" and any(i["status"] == "ok" for i in indexers),
        "services": [{"type": t, "ready": service_ready(t)} for t in SERVICES],
        "usenet": usenet,
        "indexers": indexers,
        "subtitles": subtitles_view(),
        "presets": {"providers": PROVIDERS, "indexers": [{k: p[k] for k in ("id", "name", "url", "signup")} for p in INDEXERS]},
    }


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
    return plain(msg, PROWLARR_PLAIN)


_schema = {"items": None}


def newznab_schema():
    """Prowlarr's Newznab types. Its full schema is large and slow at first (it fetches its indexer
    definitions), so it is read once, in the background at start, and kept."""
    if _schema["items"] is None:
        items = ok(*prowlarr("GET", "/indexer/schema", timeout=180), "Prowlarr")
        _schema["items"] = [s for s in items if s.get("implementation") == "Newznab"]
    return [json.loads(json.dumps(s)) for s in _schema["items"]]


def warm_schema():
    for _ in range(60):
        try:
            newznab_schema()
            log("prowlarr: %d Newznab types" % len(_schema["items"]))
            return
        except (Down, Problem, KeyError, TypeError) as e:
            log("prowlarr schema not yet:", e)
            time.sleep(30)


def add_indexer(b):
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
    profiles = ok(*prowlarr("GET", "/appprofile"), "Prowlarr")
    item.update({"name": name, "enable": True, "appProfileId": profiles[0]["id"] if profiles else 1, "priority": 25})
    item.pop("id", None)
    # The same indexer again (a new key, say): replace it rather than add a twin.
    existing = next((x for x in ok(*prowlarr("GET", "/indexer"), "Prowlarr")
                     if (field(x, "baseUrl") or "").rstrip("/").lower() == url.lower()), None)
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
    entry = {"preset": (preset or {}).get("id", "") or preset_for_url(url), "status": "ok" if good else "error", "message": message, "at": int(time.time())}
    st.setdefault("indexers", {})[str(out["id"])] = entry
    save_state(st)
    log("indexer:", name, url, "ok" if good else "error: " + message[:120])
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
        except (KeyError, IndexError, TypeError, ValueError, OSError) as e:
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
    main()
