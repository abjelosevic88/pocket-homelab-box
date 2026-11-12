"""First-boot setup of the third-party services, and the file that tells Pocket Core about them.

For each enabled service it waits until the service answers, makes a box administrator
("pocket-box") and an API key the first time (kept in STATE/<service>.json, root only), and
writes SERVICES_FILE for Core: where the service is, the administrator's credential and a
connector that makes an account for every person. Core then gives each person their own
account and key, which Pocket Watch, Music and Photos use.

The download services (SABnzbd, Radarr, Sonarr, Lidarr, Prowlarr, Bazarr) have keys the box made
before their first start (KEYS_FILE). Here they are wired to each other, again at every boot and
only where something is missing: root folders, SABnzbd as the download client (one category each),
Prowlarr's applications (full sync) and download client, Bazarr's default language profile, a login
for their web UIs. They have no per-person accounts, so Core gets them for admins only, without a
connector; Pocket Requests, Watch and Subtitles reach them through Core as the box owner.

A service that does not come up in time is left out of the file (and tried again next boot);
Core starts either way.
"""
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG = json.load(open(sys.argv[1]))
STATE = CONFIG["state_dir"]

# Once the box has its public name (modules/names.nix), Core shows the services under it.
try:
    PUBLIC_NAME = open("/var/lib/pocket-box-name/domain").read().strip()
except FileNotFoundError:
    PUBLIC_NAME = ""
if PUBLIC_NAME:
    for _svc in CONFIG["services"]:
        _svc["public_url"] = _svc["public_url"] and _svc["public_url"].replace("." + CONFIG["domain"], "." + PUBLIC_NAME)
ADMIN = "pocket-box"
JF_AUTH = 'MediaBrowser Client="Pocket Box", Device="pocket-box", DeviceId="pocket-box", Version="1"'


def log(*args):
    print(*args, flush=True)


def call(method, url, body=None, headers=None, raw=False):
    data = None if body is None else json.dumps(body).encode()
    # A service that answers its health check can still be finishing its start (Jellyfin: 503).
    end = time.time() + 300
    while True:
        req = urllib.request.Request(url, data=data, method=method, headers={"Accept": "application/json", **(headers or {})})
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=30) as res:
                text = res.read().decode() or "null"
                return text if raw else json.loads(text)
        except urllib.error.HTTPError as e:
            if e.code != 503 or time.time() > end:
                raise
            time.sleep(3)


def wait(url, seconds=600):
    end = time.time() + seconds
    while time.time() < end:
        try:
            call("GET", url, raw=True)
            return True
        except (urllib.error.URLError, OSError):
            time.sleep(3)
    return False


def load(name):
    path = os.path.join(STATE, name + ".json")
    return json.load(open(path)) if os.path.exists(path) else None


def save(name, value):
    path = os.path.join(STATE, name + ".json")
    tmp = path + ".tmp"
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        json.dump(value, f)
    os.replace(tmp, path)


def password():
    return secrets.token_urlsafe(30)


def jellyfin(base):
    info = call("GET", base + "/System/Info/Public")
    if not info.get("StartupWizardCompleted"):
        pw = password()
        call("POST", base + "/Startup/Configuration", {"UICulture": "en-US", "MetadataCountryCode": "US", "PreferredMetadataLanguage": "en"}, raw=True)
        call("GET", base + "/Startup/User")
        call("POST", base + "/Startup/User", {"Name": ADMIN, "Password": pw}, raw=True)
        call("POST", base + "/Startup/RemoteAccess", {"EnableRemoteAccess": True, "EnableAutomaticPortMapping": False}, raw=True)
        call("POST", base + "/Startup/Complete", raw=True)
        save("jellyfin", {"user": ADMIN, "password": pw})
    cred = load("jellyfin")
    if not cred:
        raise RuntimeError("Jellyfin was set up before, without the box's administrator")
    if not cred.get("api_key"):
        auth = call("POST", base + "/Users/AuthenticateByName", {"Username": cred["user"], "Pw": cred["password"]}, {"Authorization": JF_AUTH})
        hdr = {"Authorization": JF_AUTH + ', Token="%s"' % auth["AccessToken"]}
        call("POST", base + "/Auth/Keys?" + urllib.parse.urlencode({"app": "Pocket Core"}), headers=hdr, raw=True)
        keys = call("GET", base + "/Auth/Keys", headers=hdr)["Items"]
        cred["api_key"] = [k for k in keys if k.get("AppName") == "Pocket Core"][-1]["AccessToken"]
        save("jellyfin", cred)
    if not cred.get("libraries"):
        # The box's media folders, once.
        hdr = {"Authorization": 'MediaBrowser Token="%s"' % cred["api_key"]}
        have = {f["Name"] for f in call("GET", base + "/Library/VirtualFolders", headers=hdr)}
        for name, kind, path in (("Movies", "movies", CONFIG["media_dir"] + "/movies"), ("Shows", "tvshows", CONFIG["media_dir"] + "/tv")):
            if name not in have:
                q = urllib.parse.urlencode({"name": name, "collectionType": kind, "paths": path, "refreshLibrary": "false"})
                call("POST", base + "/Library/VirtualFolders?" + q, {"LibraryOptions": {}}, hdr, raw=True)
        cred["libraries"] = True
        save("jellyfin", cred)
    return {"API_KEY": cred["api_key"]}


def navidrome(base):
    cred = load("navidrome")
    if not cred:
        pw = password()
        call("POST", base + "/auth/createAdmin", {"username": ADMIN, "password": pw})
        cred = {"user": ADMIN, "password": pw}
        save("navidrome", cred)
    return {"USER": cred["user"], "PASSWORD": cred["password"]}


def immich(base):
    cred = load("immich")
    if not cred:
        pw = password()
        email = ADMIN + "@" + CONFIG["domain"]
        call("POST", base + "/api/auth/admin-sign-up", {"email": email, "password": pw, "name": "Pocket Box"})
        cred = {"email": email, "password": pw}
        save("immich", cred)
    if not cred.get("api_key"):
        token = call("POST", base + "/api/auth/login", {"email": cred["email"], "password": cred["password"]})["accessToken"]
        key = call("POST", base + "/api/api-keys", {"name": "Pocket Core", "permissions": ["all"]}, {"Authorization": "Bearer " + token})
        cred["api_key"] = key["secret"]
        save("immich", cred)
    return {"API_KEY": cred["api_key"]}


# ---- the download services ----

KEYS = json.load(open(CONFIG["keys_file"])) if CONFIG.get("arr") else {}
PORTS = CONFIG.get("ports", {})
API = {"radarr": "/api/v3", "sonarr": "/api/v3", "lidarr": "/api/v1", "prowlarr": "/api/v1"}
TITLE = {"radarr": "Radarr", "sonarr": "Sonarr", "lidarr": "Lidarr", "prowlarr": "Prowlarr"}
# Where each one's downloads and library go.
LIBRARY = {"radarr": ("movies", "movieCategory"), "sonarr": ("tv", "tvCategory"), "lidarr": ("music", "musicCategory")}


def local(t):
    return "http://127.0.0.1:%d" % PORTS[t]


def arr(t, method, path, body=None, raw=False):
    return call(method, local(t) + API[t] + path, body, {"X-Api-Key": KEYS[t]}, raw=raw)


def set_fields(item, values):
    for f in item.get("fields", []):
        if f.get("name") in values:
            f["value"] = values[f["name"]]


def arr_login(t, st):
    """A login for the web UI (Forms, required everywhere), once; the password stays in KEYS_FILE."""
    if st.get("login"):
        return
    host = arr(t, "GET", "/config/host")
    host.update({"authenticationMethod": "forms", "authenticationRequired": "enabled", "username": ADMIN,
                 "password": KEYS["password"], "passwordConfirmation": KEYS["password"]})
    arr(t, "PUT", "/config/host/%s" % host.get("id", 1), host)
    st["login"] = True


def arr_sabnzbd(t, extra):
    """SABnzbd as the download client, unless there is one already."""
    if "sabnzbd" not in CONFIG["arr"] or any(c.get("implementation") == "Sabnzbd" for c in arr(t, "GET", "/downloadclient")):
        return
    item = next(x for x in arr(t, "GET", "/downloadclient/schema") if x.get("implementation") == "Sabnzbd")
    set_fields(item, {"host": "127.0.0.1", "port": PORTS["sabnzbd"], "useSsl": False, "urlBase": "", "apiKey": KEYS["sabnzbd"], **extra})
    item.update({"name": "SABnzbd", "enable": True, "priority": 1})
    arr(t, "POST", "/downloadclient?forceSave=true", item)
    log(t, "download client: SABnzbd")


def media_app(t):
    """Radarr, Sonarr, Lidarr: library folder, SABnzbd with its own category, naming and a 1080p default."""
    st = load(t) or {}
    arr_login(t, st)
    folder, cat_field = LIBRARY[t]
    root = CONFIG["media_dir"] + "/" + folder
    if not any(r.get("path", "").rstrip("/") == root for r in arr(t, "GET", "/rootfolder")):
        body = {"path": root}
        if t == "lidarr":
            quality = {p["name"]: p["id"] for p in arr(t, "GET", "/qualityprofile")}
            meta = arr(t, "GET", "/metadataprofile")
            body.update({"name": "Music", "defaultQualityProfileId": quality.get("Standard", min(quality.values())),
                         "defaultMetadataProfileId": next((m["id"] for m in meta if m["name"] == "Standard"), meta[0]["id"]),
                         "defaultMonitorOption": "all", "defaultNewItemMonitorOption": "all", "defaultTags": []})
        arr(t, "POST", "/rootfolder", body)
        log(t, "root folder:", root)
    arr_sabnzbd(t, {cat_field: folder})
    if not st.get("naming"):
        naming = arr(t, "GET", "/config/naming")
        naming[{"radarr": "renameMovies", "sonarr": "renameEpisodes", "lidarr": "renameTracks"}[t]] = True
        arr(t, "PUT", "/config/naming/%s" % naming.get("id", 1), naming)
        st["naming"] = True
    if t in ("radarr", "sonarr") and not st.get("profiles"):
        # Pocket Requests takes the first quality profile unless told otherwise: make that HD-1080p
        # (the ones below it only on a fresh install, while nothing uses them).
        profiles = arr(t, "GET", "/qualityprofile")
        if any(p["name"] == "HD-1080p" for p in profiles):
            for p in profiles:
                if p["name"] in ("Any", "SD", "HD-720p"):
                    try:
                        arr(t, "DELETE", "/qualityprofile/%d" % p["id"], raw=True)
                    except urllib.error.HTTPError as e:
                        log(t, "kept quality profile", p["name"], e.code)
        st["profiles"] = True
    save(t, st)
    return {"API_KEY": KEYS[t]}


def radarr(base):
    return media_app("radarr")


def sonarr(base):
    return media_app("sonarr")


def lidarr(base):
    return media_app("lidarr")


def prowlarr(base):
    """Radarr, Sonarr and Lidarr as Prowlarr's applications (full sync), SABnzbd as its download client."""
    st = load("prowlarr") or {}
    arr_login("prowlarr", st)
    have = {a.get("implementation") for a in arr("prowlarr", "GET", "/applications")}
    schema = None
    for t in ("radarr", "sonarr", "lidarr"):
        if t not in CONFIG["arr"] or TITLE[t] in have:
            continue
        schema = schema or arr("prowlarr", "GET", "/applications/schema")
        item = next(x for x in schema if x.get("implementation") == TITLE[t])
        set_fields(item, {"prowlarrUrl": local("prowlarr"), "baseUrl": local(t), "apiKey": KEYS[t]})
        item.update({"name": TITLE[t], "syncLevel": "fullSync"})
        arr("prowlarr", "POST", "/applications?forceSave=true", item)
        log("prowlarr application:", TITLE[t])
    # Prowlarr's own grabs (picked by hand there) go to SABnzbd's default category.
    arr_sabnzbd("prowlarr", {"category": ""})
    save("prowlarr", st)
    return {"API_KEY": KEYS["prowlarr"]}


def sabnzbd(base):
    # The key is the box's (secretFiles); this only checks SABnzbd takes it.
    q = urllib.parse.urlencode({"mode": "get_config", "section": "misc", "keyword": "api_key", "output": "json", "apikey": KEYS["sabnzbd"]})
    if "config" not in call("GET", base + "/api?" + q):
        raise RuntimeError("SABnzbd doesn't take the box's key")
    return {"API_KEY": KEYS["sabnzbd"]}


def bazarr(base):
    """Radarr and Sonarr come from its settings (services.nix); here a default language profile, once."""
    hdr = {"X-API-KEY": KEYS["bazarr"]}
    st = load("bazarr") or {}
    if not st.get("profile"):
        profiles = call("GET", base + "/api/system/languages/profiles", headers=hdr)
        if not profiles:
            profile = {"profileId": 1, "name": "Pocket Box", "cutoff": None, "mustContain": [], "mustNotContain": [], "originalFormat": None, "tag": None,
                       "items": [{"id": 1, "language": "en", "audio_exclude": "False", "audio_only_include": "False", "hi": "False", "forced": "False"}]}
            form = [("languages-enabled", "en"), ("languages-profiles", json.dumps([profile])),
                    ("settings-general-serie_default_enabled", "true"), ("settings-general-serie_default_profile", "1"),
                    ("settings-general-movie_default_enabled", "true"), ("settings-general-movie_default_profile", "1")]
            req = urllib.request.Request(base + "/api/system/settings", data=urllib.parse.urlencode(form).encode(), method="POST", headers=hdr)
            urllib.request.urlopen(req, timeout=60).read()
            log("bazarr: default language profile (English)")
        st["profile"] = True
        save("bazarr", st)
    return {"API_KEY": KEYS["bazarr"]}


SETUP = {"jellyfin": (jellyfin, "/System/Info/Public"), "navidrome": (navidrome, "/ping"), "immich": (immich, "/api/server/ping"),
         "sabnzbd": (sabnzbd, "/api?mode=version&output=json"), "radarr": (radarr, "/ping"), "sonarr": (sonarr, "/ping"),
         "lidarr": (lidarr, "/ping"), "prowlarr": (prowlarr, "/ping"), "bazarr": (bazarr, "/")}
# Household tools without per-person accounts: admins only, no connector (Core's arr connector only
# carries events; an admin can switch it on).
BOX_ONLY = {"sabnzbd", "radarr", "sonarr", "lidarr", "prowlarr", "bazarr"}

os.makedirs(STATE, mode=0o700, exist_ok=True)
entries = []
for svc in CONFIG["services"]:
    name, base = svc["type"], svc["url"]
    setup, probe = SETUP[name]
    if not wait(base + probe):
        log(name, "did not answer in time; left out until the next boot")
        continue
    try:
        fields = setup(base)
    except (urllib.error.URLError, OSError, KeyError, IndexError, RuntimeError, ValueError, StopIteration, TypeError) as e:
        detail = e.read().decode()[:200] if isinstance(e, urllib.error.HTTPError) else ""
        log(name, "setup failed:", e, detail)
        continue
    box_only = name in BOX_ONLY
    entries.append({
        "type": name,
        "url": base,
        "public_url": svc["public_url"],
        "fields": fields,
        "audience": "admins" if box_only else "all",
        "connector": {"enabled": not box_only, "provision_on_create": not box_only},
        # Core (0.37.9+) copies the box key to the owner and admins as their own credential.
        **({"owner_credential": True} if box_only else {}),
    })
    log(name, "ready")

out = CONFIG["services_file"]
tmp = out + ".tmp"
with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump(entries, f)
os.replace(tmp, out)
log("services for Pocket Core:", ", ".join(e["type"] for e in entries) or "none")
