"""First-boot setup of the third-party services, and the file that tells Pocket Core about them.

For each enabled service it waits until the service answers, makes a box administrator
("pocket-box") and an API key the first time (kept in STATE/<service>.json, root only), and
writes SERVICES_FILE for Core: where the service is, the administrator's credential and a
connector that makes an account for every person. Core then gives each person their own
account and key, which Pocket Watch, Music and Photos use.

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


SETUP = {"jellyfin": (jellyfin, "/System/Info/Public"), "navidrome": (navidrome, "/ping"), "immich": (immich, "/api/server/ping")}

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
    except (urllib.error.URLError, OSError, KeyError, IndexError, RuntimeError, ValueError) as e:
        detail = e.read().decode()[:200] if isinstance(e, urllib.error.HTTPError) else ""
        log(name, "setup failed:", e, detail)
        continue
    entries.append({
        "type": name,
        "url": base,
        "public_url": svc["public_url"],
        "fields": fields,
        "audience": "all",
        "connector": {"enabled": True, "provision_on_create": True},
    })
    log(name, "ready")

out = CONFIG["services_file"]
tmp = out + ".tmp"
with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump(entries, f)
os.replace(tmp, out)
log("services for Pocket Core:", ", ".join(e["type"] for e in entries) or "none")
