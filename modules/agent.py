"""The Pocket Box agent: the few system changes Pocket Core's setup wizard and Settings make.

Core runs as an unprivileged, sandboxed user, so the time zone, Wi-Fi, Tailscale and the
maintenance password go through this small root service. It answers JSON on a unix socket that
only the pocket-box-agent group (Core) can open, and does nothing but the calls below.

  GET  /v1/status                  the box: name, time zone, network, Tailscale, password, disk
  GET  /v1/timezones               the zones the system knows
  PUT  /v1/timezone   {timezone}   set it, then restart the Pocket apps so they pick it up
  GET  /v1/wifi                    nearby networks (available: false without a Wi-Fi card)
  POST /v1/wifi       {ssid, password}
  POST /v1/tailscale  {auth_key?}  join the tailnet; without a key the answer has a login URL
  DELETE /v1/tailscale             leave it
  PUT  /v1/password   {password}   the console account "pocket" (locked until set here)
  GET  /v1/updates                 this release, the last update run, auto on/off, restart needed
  POST /v1/updates                 look for a release now
  PUT  /v1/updates    {auto}       nightly updates on or off
  POST /v1/restart                 restart the box (to finish a kernel update)
  GET  /v1/wizard                  is the setup wizard finished (cheap, for every page load)
  POST /v1/wizard                  the setup wizard is finished
"""
import grp
import json
import os
import re
import socketserver
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler

CONFIG = json.load(open(sys.argv[1]))
T = CONFIG["tools"]
STATE = CONFIG["state_dir"]
SOCKET = CONFIG["socket"]
USER = CONFIG["console_user"]


def run(*args, timeout=30, check=True, input=None):
    r = subprocess.run(list(args), capture_output=True, text=True, timeout=timeout, input=input)
    if check and r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout).strip() or f"{os.path.basename(args[0])} failed")
    return r.stdout


def marker(name):
    return os.path.join(STATE, name)


def flag(name):
    return os.path.exists(marker(name))


def set_flag(name):
    with open(marker(name), "w") as f:
        f.write(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + "\n")


# ---- time zone ----

def timezone():
    return run(T["timedatectl"], "show", "-p", "Timezone", "--value").strip() or "UTC"


def timezones():
    return [z for z in run(T["timedatectl"], "list-timezones").split("\n") if z]


def set_timezone(tz):
    if tz not in timezones():
        raise ValueError("unknown time zone")
    if tz == timezone():
        return
    run(T["timedatectl"], "set-timezone", tz)
    # The apps read the zone when they start. Restart them a moment after answering, so Core
    # (which asked, and is one of them) can reply first.
    # Only the apps: the box's own services (the updater, the agent itself…) must not restart.
    run(T["systemd-run"], "--on-active=3", "--unit", f"pocket-box-tz-{int(time.time())}",
        T["systemctl"], "restart", *CONFIG["app_units"], check=False)


# ---- network ----

def addresses():
    out = json.loads(run(T["ip"], "-j", "-4", "addr", "show", "scope", "global"))
    return [{"interface": i["ifname"], "address": a["local"]}
            for i in out if not i["ifname"].startswith(("tailscale", "docker", "veth", "br-"))
            for a in i.get("addr_info", []) if a.get("family") == "inet"]


def nm_fields(line):
    # nmcli -t escapes ":" inside values as "\:".
    return [f.replace("\\:", ":") for f in re.split(r"(?<!\\):", line)]


def wifi_devices():
    devs = []
    for line in run(T["nmcli"], "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", check=False).splitlines():
        d = nm_fields(line)
        if len(d) >= 4 and d[1] == "wifi":
            devs.append({"device": d[0], "state": d[2], "connection": d[3]})
    return devs


def wifi_status():
    devs = wifi_devices()
    connected = next((d["connection"] for d in devs if d["state"] == "connected"), "")
    return {"available": bool(devs), "connected": connected}


def wifi_networks():
    if not wifi_devices():
        return {"available": False, "networks": []}
    seen = {}
    out = run(T["nmcli"], "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto", timeout=40)
    for line in out.splitlines():
        f = nm_fields(line)
        if len(f) < 4 or not f[1]:
            continue
        net = {"ssid": f[1], "signal": int(f[2] or 0), "secure": f[3] not in ("", "--"), "active": f[0] == "*"}
        if f[1] not in seen or net["signal"] > seen[f[1]]["signal"] or net["active"]:
            seen[f[1]] = net
    return {"available": True, "networks": sorted(seen.values(), key=lambda n: (not n["active"], -n["signal"]))}


def wifi_connect(ssid, password):
    if not ssid:
        raise ValueError("ssid required")
    args = [T["nmcli"], "device", "wifi", "connect", ssid]
    if password:
        args += ["password", password]
    run(*args, timeout=60)


# ---- Tailscale ----

def tailscale_status():
    try:
        st = json.loads(run(T["tailscale"], "status", "--json", check=False, timeout=10) or "{}")
    except (ValueError, subprocess.TimeoutExpired):
        return {"state": "Unavailable"}
    me = st.get("Self") or {}
    return {
        "state": st.get("BackendState", "Unknown"),
        "auth_url": st.get("AuthURL", ""),
        "name": (me.get("DNSName") or "").rstrip("."),
        "addresses": st.get("TailscaleIPs") or [],
        "tailnet": (st.get("CurrentTailnet") or {}).get("Name", ""),
    }


def tailscale_up(auth_key):
    base = [T["tailscale"], "up", "--hostname", CONFIG["hostname"], "--reset"]
    if auth_key:
        run(*base, "--auth-key", auth_key, timeout=90)
        return tailscale_status()
    # Without a key, `tailscale up` waits for someone to open the login URL; let it wait in the
    # background and hand the URL back.
    subprocess.Popen(base + ["--timeout", "15m"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    end = time.time() + 25
    st = tailscale_status()
    while time.time() < end and not st.get("auth_url") and st.get("state") != "Running":
        time.sleep(1)
        st = tailscale_status()
    return st


def tailscale_down():
    run(T["tailscale"], "logout", timeout=30, check=False)


# ---- console password ----

def set_password(pw):
    if len(pw) < 8:
        raise ValueError("the password needs at least 8 characters")
    if "\n" in pw or ":" in pw:
        raise ValueError("the password cannot contain line breaks or colons")
    run(T["chpasswd"], input=f"{USER}:{pw}\n")
    set_flag("password-set")


# ---- updates (modules/updater.py does the work) ----

UPDATE = CONFIG["update_dir"]


def updates():
    try:
        st = json.load(open(os.path.join(UPDATE, "status.json")))
    except (OSError, ValueError):
        st = {}
    try:
        current = json.load(open("/etc/pocket-box/release.json"))
    except (OSError, ValueError):
        current = {}
    running = run(T["systemctl"], "is-active", "pocket-box-update.service", check=False).strip() in ("activating", "active")
    restart = os.path.realpath("/run/current-system/kernel") != os.path.realpath("/run/booted-system/kernel")
    return {"release": current, "last": st, "auto": not os.path.exists(os.path.join(UPDATE, "auto-off")),
            "running": running, "restart_needed": restart}


def check_updates():
    os.makedirs(UPDATE, exist_ok=True)
    with open(os.path.join(UPDATE, "manual"), "w") as f:
        f.write("1\n")
    run(T["systemctl"], "start", "--no-block", "pocket-box-update.service")
    return updates()


def set_auto(on):
    os.makedirs(UPDATE, exist_ok=True)
    off = os.path.join(UPDATE, "auto-off")
    if on and os.path.exists(off):
        os.remove(off)
    if not on:
        open(off, "w").close()
    return updates()


def restart_box():
    run(T["systemd-run"], "--on-active=3", "--unit", f"pocket-box-reboot-{int(time.time())}", T["systemctl"], "reboot")


# ---- disk ----

def encryption():
    src = run(T["findmnt"], "-no", "SOURCE", "/", check=False).strip()
    if not src.startswith("/dev/mapper/"):
        return {"encrypted": False, "tpm": False, "recovery_key": False}
    status = run(T["cryptsetup"], "status", os.path.basename(src), check=False)
    m = re.search(r"device:\s+(\S+)", status)
    dump = run(T["cryptsetup"], "luksDump", m.group(1), check=False) if m else ""
    return {"encrypted": True, "tpm": "systemd-tpm2" in dump, "recovery_key": "systemd-recovery" in dump}


def status():
    return {
        "hostname": CONFIG["hostname"],
        "domain": CONFIG["domain"],
        "timezone": timezone(),
        "network": {"addresses": addresses(), "wifi": wifi_status()},
        "tailscale": tailscale_status(),
        "password_set": flag("password-set"),
        "encryption": encryption(),
        "wizard_done": flag("wizard-done"),
        "updates": updates(),
    }


lock = threading.Lock()


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

    def handle_one(self):
        m, p = self.command, self.path.split("?")[0]
        if m == "GET" and p == "/v1/status":
            return status()
        if m == "GET" and p == "/v1/updates":
            return updates()
        if m == "GET" and p == "/v1/wizard":
            return {"wizard_done": flag("wizard-done")}
        if m == "GET" and p == "/v1/timezones":
            return {"timezones": timezones()}
        if m == "GET" and p == "/v1/wifi":
            return wifi_networks()
        b = self.body()
        with lock:
            if m == "PUT" and p == "/v1/timezone":
                set_timezone(str(b.get("timezone", "")))
                return {"timezone": timezone()}
            if m == "POST" and p == "/v1/wifi":
                wifi_connect(str(b.get("ssid", "")), str(b.get("password", "")))
                return wifi_status()
            if m == "POST" and p == "/v1/tailscale":
                return tailscale_up(str(b.get("auth_key", "")).strip())
            if m == "DELETE" and p == "/v1/tailscale":
                tailscale_down()
                return tailscale_status()
            if m == "PUT" and p == "/v1/password":
                set_password(str(b.get("password", "")))
                return {"password_set": True}
            if m == "POST" and p == "/v1/updates":
                return check_updates()
            if m == "PUT" and p == "/v1/updates":
                return set_auto(bool(b.get("auto")))
            if m == "POST" and p == "/v1/restart":
                restart_box()
                return {"restarting": True}
            if m == "POST" and p == "/v1/wizard":
                set_flag("wizard-done")
                return {"wizard_done": True}
        raise LookupError("not found")

    def dispatch(self):
        try:
            self.reply(200, self.handle_one())
        except LookupError as e:
            self.reply(404, {"error": str(e)})
        except ValueError as e:
            self.reply(400, {"error": str(e)})
        except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
            self.reply(502, {"error": str(e)[:300]})

    do_GET = do_PUT = do_POST = do_DELETE = dispatch


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


os.makedirs(STATE, mode=0o700, exist_ok=True)
if os.path.exists(SOCKET):
    os.remove(SOCKET)
srv = Server(SOCKET, Handler)
os.chown(SOCKET, 0, grp.getgrnam(CONFIG["group"]).gr_gid)
os.chmod(SOCKET, 0o660)
print("listening on", SOCKET, flush=True)
srv.serve_forever()
