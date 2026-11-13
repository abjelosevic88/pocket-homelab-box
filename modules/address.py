"""pocket-box-address: how the box gets its padlock, as the owner chose it.

  pocket      Pocket's free address, <random>.box.pockethomelab.net (Pocket Names)
  cloudflare  the owner's own domain on Cloudflare, <sub>.<their zone>
  own-ca      no public name: the box's own certificate, installed on each device

pocket-box-name (modules/names.py) does the work; this service only records the choice (choice.json)
and, for Cloudflare, the sign-in (private/cloudflare.json), then starts it. Two ways in:

  - a unix socket for Pocket Core (group pocket-box-agent): Core lets only admins through, and they
    may change the choice at any time;
  - 127.0.0.1:<port>, which Caddy serves at http://pocket.local/box-address/ for the landing page.
    That page has no sign-in, so there the choice can only be made once, while none is made yet,
    and only from a page that sent X-Pocket-Box (a header other sites cannot add without asking).

  GET  /v1/address                       the choice, the address, how far getting it got
  PUT  /v1/address  {mode, zone_id?, sub?, token? | pending?}
  POST /v1/address/cloudflare/zones  {token}           the zones a pasted API token can edit
  POST /v1/address/cloudflare/start  {return_url?}     "Sign in with Cloudflare": the URL to open
  POST /v1/address/cloudflare/finish {code, state}     back from Cloudflare: the zones, a pending id

Signing in with Cloudflare is OAuth with PKCE as a public client (Pocket Names publishes the client
id): the verifier never leaves this service, so the code that passes through the browser and Pocket
Names is useless without it. Pending sign-ins live in memory for 20 minutes.
"""
import base64
import hashlib
import json
import os
import re
import secrets
import socketserver
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

CONFIG = json.load(open(sys.argv[1]))
STATE = CONFIG["state_dir"]
PRIVATE = os.path.join(STATE, "private")
CHOICE = os.path.join(STATE, "choice.json")
CF_FILE = os.path.join(PRIVATE, "cloudflare.json")
DOMAIN_FILE = os.path.join(STATE, "domain")
STATUS_FILE = os.path.join(STATE, "public", "name-status.json")
FW_CFG = "/sys/firmware/qemu_fw_cfg/by_name/opt/pocket/names/raw"
CF_API = CONFIG.get("cloudflare_api", "https://api.cloudflare.com/client/v4")
MODES = ("pocket", "cloudflare", "own-ca")
SUB = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,38}[a-z0-9])?$")
RECORD_COMMENT = "Pocket Box"
# Cloudflare's "Create token" page with Zone · Read and DNS · Edit filled in.
TOKEN_PERMISSIONS = json.dumps([{"key": "zone", "type": "read"}, {"key": "dns", "type": "edit"}], separators=(",", ":"))
TOKEN_LINK = "https://dash.cloudflare.com/profile/api-tokens?" + urllib.parse.urlencode(
    {"permissionGroupKeys": TOKEN_PERMISSIONS, "accountId": "*", "zoneId": "all", "name": "Pocket Box"}, quote_via=urllib.parse.quote)


def log(*a):
    print(*a, flush=True)


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return default


def write(path, text, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode), "w") as f:
        f.write(text)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def fw_cfg():
    return read(FW_CFG).strip()


def choice():
    """The mode chosen, or None. Boxes that got a Pocket name before there was a choice keep it."""
    if fw_cfg() == "off":
        return "off"
    try:
        mode = json.loads(read(CHOICE, "{}") or "{}").get("mode")
    except json.JSONDecodeError:
        mode = None
    if mode in MODES:
        return mode
    if os.path.exists(os.path.join(PRIVATE, "account.json")) or os.path.exists(DOMAIN_FILE):
        return "pocket"
    return None


# ---- HTTP to Cloudflare and Pocket Names ----

class Problem(Exception):
    """Something the person can fix; the message is shown to them."""


def fetch(url, method="GET", body=None, token=None, form=None, timeout=20):
    headers = {"User-Agent": "pocket-box-address", "Accept": "application/json"}
    data = None
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, method=method, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {"error": raw.decode(errors="replace")[:200]}
    except (urllib.error.URLError, OSError) as e:
        raise Problem("The box can't reach the internet right now (" + str(getattr(e, "reason", e))[:80] + ").")


def cf(path, token, method="GET", body=None):
    code, out = fetch(CF_API + path, method, body, token)
    codes = {e.get("code") for e in out.get("errors", []) if isinstance(e, dict)}
    # 6003/6111/6100: a token that isn't one at all (Cloudflare answers 400); 9106/10000/10001: refused.
    if code in (401, 403) or codes & {6003, 6100, 6111, 9106, 10000, 10001}:
        raise Problem("Cloudflare didn't accept this sign-in. Check that the token can read zones and edit DNS.")
    if code >= 400 or not out.get("success", False):
        errs = "; ".join(e.get("message", "") for e in out.get("errors", []) if isinstance(e, dict)) or f"HTTP {code}"
        raise Problem("Cloudflare said: " + errs[:200])
    return out


def zones(token):
    out = cf("/zones?per_page=50&status=active", token)
    return [{"id": z["id"], "name": z["name"]} for z in out.get("result", [])]


_oauth = {"at": 0, "value": None}


def oauth_config():
    """Pocket Names' Cloudflare sign-in settings (None until it has a client), kept 5 minutes."""
    if time.time() - _oauth["at"] < 300:
        return _oauth["value"]
    code, out = fetch(CONFIG["names_server"] + "/v1/cloudflare", timeout=10)
    _oauth.update(at=time.time(), value=out.get("oauth") if code == 200 else None)
    return _oauth["value"]


def records_in_the_way(token, zone_id, domain):
    """Records at <domain> or *.<domain> that the box didn't make: the box must not take those over."""
    found = []
    for name in (domain, "*." + domain):
        out = cf("/zones/" + zone_id + "/dns_records?per_page=50&name=" + urllib.parse.quote(name), token)
        found += [r for r in out.get("result", []) if (r.get("comment") or "") != RECORD_COMMENT]
    return found


# ---- pending Cloudflare sign-ins (memory only) ----

pending_lock = threading.Lock()
starts = {}     # state → {verifier, oauth, redirect_uri, at}
signins = {}    # pending id → {cred, at}
TTL = 20 * 60


def sweep():
    now = time.time()
    for d in (starts, signins):
        for k in [k for k, v in d.items() if now - v["at"] > TTL]:
            del d[k]


def b64url(raw):
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def start_signin(return_url):
    oauth = oauth_config()
    if not oauth:
        raise Problem("Signing in with Cloudflare isn't available yet. Use an API token instead.")
    verifier = b64url(secrets.token_bytes(48))
    state = b64url(json.dumps({"r": return_url, "n": secrets.token_hex(12)}).encode())
    with pending_lock:
        sweep()
        if len(starts) > 50:
            raise Problem("Too many sign-ins started; try again in a few minutes.")
        starts[state] = {"verifier": verifier, "oauth": oauth, "at": time.time()}
    q = {
        "response_type": "code",
        "client_id": oauth["client_id"],
        "redirect_uri": oauth["redirect_uri"],
        "scope": oauth["scopes"],
        "state": state,
        "code_challenge": b64url(hashlib.sha256(verifier.encode()).digest()),
        "code_challenge_method": "S256",
    }
    return {"url": oauth["authorize"] + "?" + urllib.parse.urlencode(q, quote_via=urllib.parse.quote)}


def finish_signin(code, state):
    with pending_lock:
        sweep()
        s = starts.pop(state, None)
    if not s:
        raise Problem("This sign-in has expired or was already used. Start again.")
    o = s["oauth"]
    status, out = fetch(o["token"], "POST", form={
        "grant_type": "authorization_code", "code": code, "redirect_uri": o["redirect_uri"],
        "client_id": o["client_id"], "code_verifier": s["verifier"]})
    if status != 200 or not out.get("access_token"):
        raise Problem("Cloudflare didn't finish the sign-in (" + str(out.get("error_description") or out.get("error") or status)[:120] + "). Start again.")
    cred = {"kind": "oauth", "access_token": out["access_token"], "refresh_token": out.get("refresh_token", ""),
            "expires_at": int(time.time()) + int(out.get("expires_in") or 3600),
            "client_id": o["client_id"], "token_url": o["token"], "scope": out.get("scope", "")}
    zs = zones(cred["access_token"])
    pid = secrets.token_urlsafe(18)
    with pending_lock:
        signins[pid] = {"cred": cred, "at": time.time()}
    return {"pending": pid, "zones": zs}


# ---- the choice ----

def status_info():
    try:
        return json.loads(read(STATUS_FILE, "{}") or "{}")
    except json.JSONDecodeError:
        return {}


def address_view(admin):
    mode = choice()
    cfj = {}
    try:
        cfj = json.loads(read(CF_FILE, "{}") or "{}")
    except json.JSONDecodeError:
        pass
    oauth = None
    if mode is None or admin:
        try:
            oauth = oauth_config()
        except Problem:
            oauth = None
    return {
        "mode": mode,
        "chosen": mode is not None,
        "can_choose": mode != "off" and (admin or mode is None),
        "domain": read(DOMAIN_FILE).strip(),
        "status": status_info(),
        "problem": (json.loads(read(os.path.join(STATE, "problem.json"), "null") or "null") if admin else None),
        "cloudflare": ({"zone": cfj.get("zone"), "sub": cfj.get("sub"), "domain": f"{cfj.get('sub')}.{cfj.get('zone')}",
                        "kind": cfj.get("kind")} if cfj.get("zone") and mode == "cloudflare" else None),
        "options": {"oauth": bool(oauth), "token_link": TOKEN_LINK},
    }


def set_choice(b, admin):
    mode = b.get("mode")
    current = choice()
    if current == "off":
        raise Problem("Public names are turned off on this box.")
    if not admin and current is not None:
        raise PermissionError("The box's address is already chosen. Change it in Pocket Core → Settings → This box.")
    if mode not in MODES:
        raise ValueError("mode must be pocket, cloudflare or own-ca")
    if mode == "cloudflare":
        sub = str(b.get("sub") or "pocket").strip().lower()
        if not SUB.match(sub):
            raise Problem("The name can have letters, digits and dashes (up to 40), like “pocket” or “home”.")
        if b.get("pending"):
            with pending_lock:
                p = signins.pop(str(b["pending"]), None)
            if not p:
                raise Problem("This Cloudflare sign-in has expired. Sign in again.")
            cred = p["cred"]
            token = cred["access_token"]
        elif b.get("token"):
            token = str(b["token"]).strip()
            cred = {"kind": "token", "token": token}
        else:
            raise ValueError("sign in with Cloudflare or paste an API token")
        zone = next((z for z in zones(token) if z["id"] == b.get("zone_id")), None)
        if not zone:
            raise Problem("That domain isn't one this Cloudflare sign-in can change.")
        domain = f"{sub}.{zone['name']}"
        if records_in_the_way(token, zone["id"], domain):
            raise Problem(f"{domain} is already used in your Cloudflare DNS. Pick another name, or remove those records first.")
        cred.update({"zone_id": zone["id"], "zone": zone["name"], "sub": sub})
        os.makedirs(PRIVATE, mode=0o700, exist_ok=True)
        os.chmod(PRIVATE, 0o700)
        old = read(CF_FILE)
        if old:  # the box removes the records it made under the old name when the new one works
            write(os.path.join(PRIVATE, "cloudflare-old.json"), old, 0o600)
        write(CF_FILE, json.dumps(cred), 0o600)
        log("address: cloudflare", domain, "(" + cred["kind"] + ")")
    else:
        log("address:", mode)
    write(CHOICE, json.dumps({"mode": mode, "at": int(time.time()), "by": "core" if admin else "landing"}))
    if mode != "own-ca" and read(DOMAIN_FILE).strip() == "":
        write(STATUS_FILE, json.dumps({"state": "asking", "message": "", "at": int(time.time())}))
    subprocess.run([CONFIG["tools"]["systemctl"], "start", "--no-block", "pocket-box-name.service"], check=False)
    return address_view(admin)


# ---- HTTP ----

lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    admin = False

    def log_message(self, fmt, *args):
        print(("core " if self.admin else "landing ") + self.command, self.path.split("?")[0], fmt % args, flush=True)

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
            raise ValueError("request too large")
        try:
            b = json.loads(self.rfile.read(n) or b"{}") if n else {}
        except ValueError:
            raise ValueError("not JSON")
        if not isinstance(b, dict):
            raise ValueError("not a JSON object")
        return b

    def landing_ok(self):
        """The landing page's changes come from that page only."""
        if self.admin:
            return True
        if self.headers.get("X-Pocket-Box") != "1":
            return False
        origin = self.headers.get("Origin")
        return origin is None or origin == CONFIG["landing"]

    def handle_one(self):
        m, p = self.command, self.path.split("?")[0]
        if m == "GET" and p == "/v1/address":
            return address_view(self.admin)
        if m not in ("PUT", "POST"):
            raise LookupError("not found")
        if not self.landing_ok():
            raise PermissionError("not from the box's page")
        b = self.body()
        if not self.admin and choice() is not None:
            raise PermissionError("The box's address is already chosen. Change it in Pocket Core → Settings → This box.")
        if m == "PUT" and p == "/v1/address":
            with lock:
                return set_choice(b, self.admin)
        if m == "POST" and p == "/v1/address/cloudflare/zones":
            token = str(b.get("token") or "").strip()
            if not token:
                raise ValueError("paste the API token")
            return {"zones": zones(token)}
        if m == "POST" and p == "/v1/address/cloudflare/start":
            ret = str(b.get("return_url") or "") if self.admin else CONFIG["landing"] + "/"
            u = urllib.parse.urlparse(ret)
            if u.scheme not in ("http", "https") or not u.netloc:
                raise ValueError("return_url must be the page to come back to")
            return start_signin(ret)
        if m == "POST" and p == "/v1/address/cloudflare/finish":
            return finish_signin(str(b.get("code") or ""), str(b.get("state") or ""))
        raise LookupError("not found")

    def dispatch(self):
        try:
            self.reply(200, self.handle_one())
        except LookupError as e:
            self.reply(404, {"error": str(e)})
        except PermissionError as e:
            self.reply(403, {"error": str(e)})
        except ValueError as e:
            self.reply(400, {"error": str(e)})
        except Problem as e:
            self.reply(422, {"error": str(e)})
        except (RuntimeError, OSError, subprocess.SubprocessError) as e:
            log("error:", e)
            self.reply(502, {"error": str(e)[:300]})

    do_GET = do_PUT = do_POST = dispatch


class CoreHandler(Handler):
    admin = True


class UnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def get_request(self):
        # BaseHTTPRequestHandler wants a client address; a unix socket has none.
        conn, _ = super().get_request()
        return conn, ("core", 0)


class TCPServer(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True


def main():
    os.makedirs(PRIVATE, mode=0o700, exist_ok=True)
    sock = CONFIG["socket"]
    if os.path.exists(sock):
        os.remove(sock)
    unix = UnixServer(sock, CoreHandler)
    import grp
    os.chown(sock, 0, grp.getgrnam(CONFIG["group"]).gr_gid)
    os.chmod(sock, 0o660)
    tcp = TCPServer(("127.0.0.1", CONFIG["port"]), Handler)
    threading.Thread(target=unix.serve_forever, daemon=True).start()
    log("listening on", sock, "and 127.0.0.1:%d" % CONFIG["port"])
    tcp.serve_forever()


if __name__ == "__main__":
    main()
