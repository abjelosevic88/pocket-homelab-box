"""pocket-box-installer: Install and Remove for the Pocket apps, behind Pocket Core's app store.

Every Pocket app ships in the box's system (apps.nix), each as its own service. An app runs only while
its marker /var/lib/pocket-box/apps/<slug> exists (the units' ConditionPathExists), so Install makes the
marker and starts the app (it then registers with Core on its own), and Remove stops it and drops the
marker. Its data stays in /var/lib/pocket-<slug>: installing it again brings everything back. Apps come
and go with the box's nightly updates; a new one starts out not installed.

This speaks the protocol of Core's installer agent (internal/installer in Pocket Core), on a unix socket
only Core's group can open, with a bearer token on top:

  GET  /v1/status            what kind of installer this is
  GET  /v1/catalog           every app the box carries, installed or not
  POST /v1/install   {slug}  → a job
  POST /v1/uninstall {slug}  → a job
  POST /v1/update            refused: apps update with the box
  GET  /v1/jobs/<id>
"""
import hmac
import json
import os
import secrets
import socketserver
import subprocess
import sys
import threading
import time
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler

CONFIG = json.load(open(sys.argv[1]))
T = CONFIG["tools"]
SOCKET = CONFIG["socket"]
MARKERS = CONFIG["markers"]
CATALOG = CONFIG["apps"]  # slug -> {title, version, port}
DOMAIN = CONFIG["domain"]


def token():
    for line in open(CONFIG["token_file"]):
        if line.startswith("INSTALLER_TOKEN="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("no INSTALLER_TOKEN in " + CONFIG["token_file"])


TOKEN = token()


def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def public_url(slug):
    """https://<slug>.<the box's public name, or its .local domain>."""
    try:
        name = open(CONFIG["name_file"]).read().strip()
    except FileNotFoundError:
        name = ""
    return f"https://{slug}.{name or DOMAIN}"


def installed(slug):
    return os.path.exists(os.path.join(MARKERS, slug))


def systemctl(*args, timeout=180):
    r = subprocess.run([T["systemctl"], *args], capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stderr or r.stdout).strip()


def active(slug):
    return systemctl("is-active", "--quiet", f"pocket-{slug}.service")[0] == 0


_about = {"at": 0, "apps": {}}


def about():
    """Descriptions, categories and icons from the public Pocket app catalog, for the store's list.

    Only words and pictures: what runs is always the box's own build. Kept for six hours; offline
    (or if the catalog changes shape) the list simply shows the names."""
    if time.time() - _about["at"] < 6 * 3600:
        return _about["apps"]
    _about["at"] = time.time()
    try:
        req = urllib.request.Request(CONFIG["catalog_url"], headers={"User-Agent": "pocket-box-installer"})
        with urllib.request.urlopen(req, timeout=10) as r:
            doc = json.load(r)
        cat = doc.get("catalog", doc)
        if isinstance(cat, str):
            cat = json.loads(cat)
        _about["apps"] = {a["slug"]: a for a in cat.get("apps", []) if isinstance(a, dict) and "slug" in a}
    except (OSError, ValueError, KeyError, AttributeError, TypeError) as e:
        print("app catalog not read:", e, flush=True)
        _about["at"] = time.time() - 6 * 3600 + 600  # try again in ten minutes
    return _about["apps"]


def release(slug):
    app = CATALOG[slug]
    on = installed(slug)
    more = about().get(slug, {})
    return {
        "slug": slug, "name": app["title"], "repo": "", "repo_url": str(more.get("repo_url", "")),
        "description": str(more.get("description", "")), "category": str(more.get("category", "")),
        "icon": str(more.get("icon", "")), "page": str(more.get("page", "")),
        "version": app["version"], "tag": "v" + app["version"], "image": "", "container": "",
        "present": False, "available": True, "running": app["version"] if on else "",
        "updatable": False, "update_note": "updates with the box every night",
        "requires": {},
    }


jobs = {}
jobs_lock = threading.Lock()
work_lock = threading.Lock()  # one install or removal at a time


class Job:
    def __init__(self, kind, slug):
        self.id = secrets.token_hex(8)
        self.kind, self.slug = kind, slug
        self.state, self.log, self.error, self.result = "running", [], "", None
        self.started, self.ended = now(), None

    def say(self, msg):
        self.log.append(msg)
        print(self.kind, self.slug, msg, flush=True)

    def finish(self, state, error=""):
        self.state, self.error, self.ended = state, error, now()

    def view(self):
        v = {"id": self.id, "kind": self.kind, "slug": self.slug, "state": self.state, "log": list(self.log),
             "started_at": self.started}
        if self.error:
            v["error"] = self.error
        if self.result is not None:
            v["result"] = self.result
        if self.ended:
            v["ended_at"] = self.ended
        return v


# Where the SDK keeps an app's Core registration. Remove unregisters the app in Core, which revokes
# that token, and an app never enrolls again by itself with a revoked one; so these go on Remove and
# before every Install, and the app registers afresh with the box's registration key. The same files
# Core's own installer drops when it brings an app's data back (internal/installer/restore.go).
CORE_TOKEN_FILES = ("core.token", "core.token.oidc.json")


def forget_core(slug):
    gone = 0
    for f in CORE_TOKEN_FILES:
        try:
            os.remove(os.path.join(CONFIG["data_root"], f"pocket-{slug}", f))
            gone += 1
        except FileNotFoundError:
            pass
    return gone


def install(job):
    slug, app = job.slug, CATALOG[job.slug]
    os.makedirs(MARKERS, mode=0o755, exist_ok=True)
    open(os.path.join(MARKERS, slug), "w").close()
    # Core asks only for apps it doesn't know: one still running here (removed before this fix, or its
    # registration lost) is started again with a fresh registration.
    if active(slug):
        job.say(f"{app['title']} runs but is not registered with Pocket Core; starting it again")
        systemctl("stop", f"pocket-{slug}.service")
    if forget_core(slug):
        job.say("Its old Pocket Core registration is cleared, so it registers afresh")
    job.say(f"Switching {app['title']} on")
    code, out = systemctl("start", f"pocket-{slug}.service")
    if code != 0 or not active(slug):
        os.remove(os.path.join(MARKERS, slug))
        raise RuntimeError(f"{app['title']} did not start: {out[-300:] or 'see journalctl -u pocket-' + slug}")
    job.say(f"{app['title']} {app['version']} is running")
    job.result = {"app_url": f"http://127.0.0.1:{app['port']}", "public_url": public_url(slug),
                  "port": app["port"], "version": app["version"]}


def uninstall(job):
    slug, app = job.slug, CATALOG[job.slug]
    job.say(f"Switching {app['title']} off")
    systemctl("stop", f"pocket-{slug}.service")
    try:
        os.remove(os.path.join(MARKERS, slug))
    except FileNotFoundError:
        pass
    forget_core(slug)  # Core revokes it now; installing again registers afresh
    job.say("Stopped; it no longer starts with the box. Its data stays on the box.")
    job.result = {"version": app["version"]}


def start(kind, body):
    slug = str(body.get("slug", ""))
    if slug == "core":
        raise PermissionError("Pocket Core is always on")
    if slug not in CATALOG:
        raise LookupError(f"there is no app {slug!r} on this box")
    job = Job(kind, slug)
    with jobs_lock:
        jobs[job.id] = job

    def go():
        with work_lock:
            try:
                (install if kind == "install" else uninstall)(job)
                job.finish("done")
            except Exception as e:  # noqa: BLE001 - every failure ends the job with its reason
                job.say(str(e))
                job.finish("failed", str(e))

    threading.Thread(target=go, daemon=True).start()
    return job.view()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(self.command, self.path, fmt % args, flush=True)

    def reply(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}

    def route(self):
        m, p = self.command, self.path.split("?")[0]
        if m == "GET" and p == "/v1/status":
            return 200, {"owner": "pocket-box", "apps_dir": "/var/lib", "archive_dir": "",
                         "public_url": public_url("{slug}"), "proxy": False, "source": "box",
                         "source_url": "", "platform": CONFIG["platform"]}
        if m == "GET" and p == "/v1/catalog":
            return 200, {"apps": [release(s) for s in sorted(CATALOG, key=lambda s: CATALOG[s]["title"].lower())]}
        if m == "POST" and p == "/v1/install":
            return 202, start("install", self.body())
        if m == "POST" and p == "/v1/uninstall":
            return 202, start("uninstall", self.body())
        if m == "POST" and p == "/v1/update":
            return 409, {"error": "Apps on a Pocket Box update with the box every night"}
        if m == "GET" and p.startswith("/v1/jobs/"):
            with jobs_lock:
                job = jobs.get(p.rsplit("/", 1)[1])
            if not job:
                raise LookupError("no such job")
            return 200, job.view()
        raise LookupError("not found")

    def dispatch(self):
        auth = self.headers.get("Authorization", "")
        if not hmac.compare_digest(auth.encode(), ("Bearer " + TOKEN).encode()):
            return self.reply(401, {"error": "wrong installer token"})
        try:
            self.reply(*self.route())
        except LookupError as e:
            self.reply(404, {"error": str(e)})
        except PermissionError as e:
            self.reply(403, {"error": str(e)})
        except FileExistsError as e:
            self.reply(409, {"error": str(e)})
        except ValueError as e:
            self.reply(400, {"error": str(e)})

    do_GET = do_POST = dispatch


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def prune():
    """Forgets finished jobs after a day."""
    while True:
        time.sleep(3600)
        cut = time.time() - 86400
        with jobs_lock:
            for k in [k for k, j in jobs.items() if j.ended and datetime.fromisoformat(j.ended.replace("Z", "+00:00")).timestamp() < cut]:
                del jobs[k]


if os.path.exists(SOCKET):
    os.remove(SOCKET)
srv = Server(SOCKET, Handler)
os.chmod(SOCKET, 0o660)
threading.Thread(target=prune, daemon=True).start()
print("listening on", SOCKET, "with", len(CATALOG), "apps", flush=True)
srv.serve_forever()
