"""pocket-box-name: the box's public name and a certificate every browser trusts.

How, the owner chooses on http://pocket.local or in Core (modules/address.py writes choice.json):
  pocket      Pocket's free address, below (until 2026-11 the only way; boxes named then keep it),
  cloudflare  their own domain on Cloudflare: the box keeps <sub>.<zone> and *.<sub>.<zone> pointed
              at its home address with their token and gets the certificate over DNS-01 itself,
              without Pocket Names,
  own-ca      no public name: https://<app>.pocket.local with the box's own CA.
Nothing happens until there is a choice (a new box doesn't tell Pocket Names its home address unless
the owner picked that). Switching moves the box over once the new name works, then lets the old one go.

Pocket's free address. Each run:
  1. registers with Pocket Names once (a random name like x7k2m9.box.pockethomelab.com and a token),
  2. points that name and *.name at the box's home address, again when it changes and twice a day
     as a sign of life (names of boxes that go quiet for months are given back),
  3. gets a Let's Encrypt certificate for name and *.name over DNS-01 (lego's httpreq provider talks
     to Pocket Names, which only ever sees the challenge; the private key stays here), and renews it
     30 days before it runs out,
  4. once the certificate is there: Caddy serves every app on the new name too, the box resolves the
     new names itself (/etc/hosts), and, when the name is new, the apps are restarted so their
     public URLs (rewritten by pocket-box-env from the domain file) use it.

Until all of that worked once, nothing changes: the box keeps https://<app>.pocket.local and its own CA.
Meanwhile public/name-status.json tells the landing page (http://pocket.local) how far it got, so a
phone opened in the first minutes waits for the name instead of offering the certificate steps.
Two timers run this: the regular one, and a quick one every 3 minutes until the box has its name; a
lock keeps them from running at once.
"""
import base64
import fcntl
import ipaddress
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG = json.load(open(sys.argv[1]))
T = CONFIG["tools"]
STATE = CONFIG["state_dir"]
PRIVATE = os.path.join(STATE, "private")
ACCOUNT = os.path.join(PRIVATE, "account.json")
LEGO = os.path.join(PRIVATE, "lego")
TLS = os.path.join(STATE, "tls")
DOMAIN_FILE = os.path.join(STATE, "domain")
SENT = os.path.join(PRIVATE, "address.json")
FW_CFG = "/sys/firmware/qemu_fw_cfg/by_name/opt/pocket/names/raw"
CHOICE = os.path.join(STATE, "choice.json")
CF_FILE = os.path.join(PRIVATE, "cloudflare.json")
CF_OLD = os.path.join(PRIVATE, "cloudflare-old.json")
CF_SENT = os.path.join(PRIVATE, "cloudflare-address.json")
CF_API = CONFIG.get("cloudflare_api", "https://api.cloudflare.com/client/v4")
RECORD_COMMENT = "Pocket Box"


def log(*a):
    print(*a, flush=True)


def run(*cmd, check=True, env=None, timeout=600):
    r = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"{os.path.basename(cmd[0])} failed ({r.returncode}): {(r.stderr or r.stdout).strip()[-800:]}")
    return r.stdout


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return default


def write(path, text, mode=0o644, group=None):
    """Writes atomically; returns whether the content changed."""
    if read(path, None) == text:
        if group is not None:
            shutil.chown(path, group=group)
        os.chmod(path, mode)
        return False
    tmp = path + ".tmp"
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode), "w") as f:
        f.write(text)
    if group is not None:
        shutil.chown(tmp, group=group)
    os.chmod(tmp, mode)
    os.replace(tmp, path)
    return True


class Rejected(Exception):
    pass


class Waiting(Exception):
    """Pocket Names knows the box but holds it back for now (approval, or busy); it asks again."""


class Limited(Exception):
    """Pocket Names turned the box away because of one of its limits (HTTP 429); it asks again, but
    the owner should hear which limit it was and how long it lasts."""


# What each of Pocket Names' limits means for the owner, by the start of its error text.
LIMITS = [
    ("too many new names from this address",
     "Pocket Names gives each home internet address 3 new box names a day, and this address has used them "
     "today (installing the box again counts as a new name). The box asks again by itself and gets its name "
     "as soon as one frees up, within a day at most."),
    ("too many new names today",
     "Pocket Names has given out all of today's new names. The box asks again by itself and gets its name "
     "tomorrow at the latest."),
    ("too many new boxes this week",
     "Pocket Names has reached this week's limit for new certificates. The box asks again by itself and "
     "gets its padlock in a few days."),
    ("too many certificate attempts",
     "This box asked for its certificate too often this week. It asks again by itself in a few days."),
]


def limit_message(detail):
    try:
        text = str(json.loads(detail).get("error") or detail)
    except (ValueError, AttributeError):
        text = detail
    for start, message in LIMITS:
        if text.startswith(start):
            return message
    return "Pocket Names is holding new names back for now (" + text.strip()[:120] + "). The box asks again by itself."


def status(state, message=""):
    """How far getting the name got, for the landing page: choose | asking | certificate | waiting |
    limited | offline | failed | ready | own-ca | off. Only until the box has its name; renewals later (and a
    switch to another name, while the old one still works) don't show here."""
    if state not in ("ready", "own-ca") and os.path.exists(DOMAIN_FILE):
        return
    os.makedirs(os.path.join(STATE, "public"), exist_ok=True)
    write(os.path.join(STATE, "public", "name-status.json"),
          json.dumps({"state": state, "message": message, "at": int(time.time())}))


PROBLEM = os.path.join(STATE, "problem.json")


def problem(state=None, message=""):
    """The last thing that went wrong, for Core (Settings → This box), even once the box has its name
    (a renewal, a lapsed Cloudflare sign-in); cleared by the next run that works."""
    if state is None:
        if os.path.exists(PROBLEM):
            os.remove(PROBLEM)
        return
    write(PROBLEM, json.dumps({"state": state, "message": message, "at": int(time.time())}))


def api(method, path, body=None, account=None):
    req = urllib.request.Request(CONFIG["server"] + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", "User-Agent": "pocket-box-name"})
    if account:
        cred = base64.b64encode(f"{account['name']}:{account['token']}".encode()).decode()
        req.add_header("Authorization", "Basic " + cred)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        if e.code == 401:
            raise Rejected(detail)
        if e.code == 429:
            raise Limited(limit_message(detail))
        if e.code in (403, 503):
            raise Waiting(f"Pocket Names {method} {path}: HTTP {e.code} {detail}")
        raise RuntimeError(f"Pocket Names {method} {path}: HTTP {e.code} {detail}")


def account():
    if os.path.exists(ACCOUNT):
        return json.load(open(ACCOUNT))
    a = api("POST", "/v1/register")
    write(ACCOUNT, json.dumps(a), 0o600)
    log("registered as", a["domain"])
    return a


def home_address():
    """The IPv4 address the box reaches the internet from, if it is a home-network one."""
    try:
        routes = json.loads(run(T["ip"], "-j", "-4", "route", "get", "1.1.1.1"))
        ip = routes[0].get("prefsrc", "")
        a = ipaddress.ip_address(ip)
    except (RuntimeError, ValueError, IndexError, KeyError, json.JSONDecodeError):
        return None
    return ip if a.version == 4 and a.is_private and not a.is_loopback and not a.is_link_local else None


def send_address(acct):
    ip = home_address()
    if not ip:
        log("no home-network IPv4 address; the name keeps its last one")
        return
    last = json.loads(read(SENT, "{}") or "{}")
    if last.get("ip") == ip and last.get("name") == acct["name"] and time.time() - last.get("at", 0) < 12 * 3600:
        return
    api("PUT", "/v1/address", {"ip": ip}, acct)
    write(SENT, json.dumps({"ip": ip, "name": acct["name"], "at": int(time.time())}), 0o600)
    log(acct["domain"], "→", ip)


def cert_paths(domain):
    base = os.path.join(LEGO, "certificates", domain)
    return base + ".crt", base + ".key"


def cert_ok(domain, days=30):
    crt, key = cert_paths(domain)
    if not (os.path.exists(crt) and os.path.exists(key)):
        return False
    r = subprocess.run([T["openssl"], "x509", "-in", crt, "-noout", "-checkend", str(days * 86400)], capture_output=True)
    if r.returncode != 0:
        return False
    names = run(T["openssl"], "x509", "-in", crt, "-noout", "-ext", "subjectAltName", check=False)
    return f"DNS:{domain}" in names and f"DNS:*.{domain}" in names


def get_cert(domain, provider, extra_env):
    env = {"PATH": "/run/current-system/sw/bin", "HOME": PRIVATE, **extra_env}
    log("asking Let's Encrypt for a certificate for", domain, "and *." + domain, "(" + provider + ")")
    run(T["lego"], "--log.format", "text", "run", "--path", LEGO, "--server", CONFIG["acme_server"],
        # Let's Encrypt asks Cloudflare's own name servers, so that is the only propagation check: public
        # resolvers can remember "no such record" from before the challenge was made, and time out.
        "--accept-tos", "--dns", provider, "--dns.resolvers", "1.1.1.1:53,8.8.8.8:53",
        "--dns.propagation.disable-rns",
        "--renew-days", "30", "--no-random-sleep",
        "-d", domain, "-d", "*." + domain, env=env, timeout=900)


def pocket_cert_env(acct):
    return {"HTTPREQ_ENDPOINT": CONFIG["server"] + "/acme",
            "HTTPREQ_USERNAME": acct["name"], "HTTPREQ_PASSWORD": acct["token"]}


def caddy_site(domain):
    """Every app on <app>.<domain>, with the Let's Encrypt certificate; the bare name opens Core."""
    lines = [f"https://{domain}, https://*.{domain} {{",
             f"\ttls {TLS}/cert.pem {TLS}/key.pem"]
    for name, port in sorted(CONFIG["sites"].items()):
        lines += [f"\t@{name} host {name}.{domain}", f"\thandle @{name} {{", f"\t\treverse_proxy 127.0.0.1:{port}", "\t}"]
    lines += [f"\t@bare host {domain}", "\thandle @bare {", f"\t\tredir https://core.{domain}{{uri}}", "\t}",
              "\thandle {", "\t\trespond \"No such app on this box\" 404", "\t}", "}", ""]
    return "\n".join(lines)


def hosts(domain):
    names = [domain] + [f"{n}.{domain}" for n in sorted(CONFIG["sites"])]
    return "".join("127.0.0.1 " + " ".join(names[i:i + 8]) + "\n" for i in range(0, len(names), 8))


def install(domain):
    """Hands the certificate to Caddy and switches the box over; returns whether the name is new."""
    crt, key = cert_paths(domain)
    os.makedirs(TLS, exist_ok=True)
    shutil.chown(TLS, group=CONFIG["caddy_group"])
    os.chmod(TLS, 0o750)
    changed = write(os.path.join(TLS, "cert.pem"), read(crt), 0o640, CONFIG["caddy_group"])
    changed |= write(os.path.join(TLS, "key.pem"), read(key), 0o640, CONFIG["caddy_group"])
    os.makedirs(os.path.join(STATE, "caddy"), exist_ok=True)
    changed |= write(os.path.join(STATE, "caddy", "public.caddy"), caddy_site(domain))
    os.makedirs(os.path.join(STATE, "public"), exist_ok=True)
    write(os.path.join(STATE, "public", "name.json"), json.dumps({"domain": domain, "core": f"https://core.{domain}"}))
    write(os.path.join(STATE, "hosts"), hosts(domain))
    write_etc_hosts()
    if changed:
        run(T["systemctl"], "reload-or-restart", "caddy.service")
        log("Caddy serves", "*." + domain)
    if read(DOMAIN_FILE).strip() == domain:
        return False
    write(DOMAIN_FILE, domain + "\n")
    return True


def uninstall():
    """Back to https://<app>.pocket.local with the box's own CA (the owner chose that)."""
    for f in (os.path.join(STATE, "caddy", "public.caddy"), os.path.join(STATE, "public", "name.json"),
              os.path.join(STATE, "hosts"), DOMAIN_FILE):
        if os.path.exists(f):
            os.remove(f)
    write_etc_hosts()
    run(T["systemctl"], "reload-or-restart", "caddy.service")
    log("public name off: back to the box's own certificate")


def write_etc_hosts():
    """/etc/hosts is a copy (environment.etc.hosts.mode); this adds the box's own public names to it."""
    if os.path.islink("/etc/hosts"):
        return
    text = read("/etc/static/hosts") + read(os.path.join(STATE, "hosts"), "")
    write("/etc/hosts", text)


def switch_apps():
    """The apps read their public URLs at start; restart them so they register under the new name.

    One queued job for all of them: systemd keeps the order (the media services' setup rewrites Core's
    service list before Core starts, Core before the apps) without this run waiting for it all."""
    log("restarting the apps on the new name")
    run(T["systemctl"], "restart", "--no-block", *CONFIG["backends_units"], *CONFIG["app_units"])


# ---- the owner's own domain on Cloudflare ----

def cf(path, token, method="GET", body=None):
    req = urllib.request.Request(CF_API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", "User-Agent": "pocket-box-name",
                                          "Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        if e.code in (401, 403):
            raise SignIn(f"Cloudflare refused the box's sign-in (HTTP {e.code})")
        raise RuntimeError(f"Cloudflare {method} {path.split('?')[0]}: HTTP {e.code} {detail}")


class SignIn(Exception):
    """The Cloudflare sign-in no longer works: the owner signs in again in Core."""


def cf_token(c):
    """A working token: a pasted API token as it is; a Cloudflare sign-in refreshed when it runs out."""
    if c.get("kind") != "oauth":
        return c["token"]
    if time.time() < c.get("expires_at", 0) - 600:
        return c["access_token"]
    if not c.get("refresh_token"):
        raise SignIn("the Cloudflare sign-in ran out")
    data = urllib.parse.urlencode({"grant_type": "refresh_token", "refresh_token": c["refresh_token"],
                                   "client_id": c["client_id"]}).encode()
    req = urllib.request.Request(c["token_url"], data=data, method="POST",
                                 headers={"Content-Type": "application/x-www-form-urlencoded", "User-Agent": "pocket-box-name"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            out = json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code in (400, 401):
            raise SignIn("Cloudflare no longer accepts the box's sign-in")
        raise RuntimeError(f"Cloudflare token refresh: HTTP {e.code}")
    c.update(access_token=out["access_token"], refresh_token=out.get("refresh_token") or c["refresh_token"],
             expires_at=int(time.time()) + int(out.get("expires_in") or 3600))
    write(CF_FILE, json.dumps(c), 0o600)
    log("refreshed the Cloudflare sign-in")
    return c["access_token"]


def cf_point(c, token, ip):
    """<sub>.<zone> and *.<sub>.<zone> → the home address, as A records only the box looks after."""
    domain = f"{c['sub']}.{c['zone']}"
    last = json.loads(read(CF_SENT, "{}") or "{}")
    if last.get("ip") == ip and last.get("domain") == domain and time.time() - last.get("at", 0) < 12 * 3600:
        return
    for name in (domain, "*." + domain):
        out = cf(f"/zones/{c['zone_id']}/dns_records?type=A&name={urllib.parse.quote(name)}", token)
        mine = [r for r in out.get("result", []) if (r.get("comment") or "") == RECORD_COMMENT]
        rec = {"type": "A", "name": name, "content": ip, "ttl": 300, "proxied": False, "comment": RECORD_COMMENT}
        if mine:
            if mine[0].get("content") != ip:
                cf(f"/zones/{c['zone_id']}/dns_records/{mine[0]['id']}", token, "PUT", rec)
        else:
            cf(f"/zones/{c['zone_id']}/dns_records", token, "POST", rec)
    write(CF_SENT, json.dumps({"ip": ip, "domain": domain, "at": int(time.time())}), 0o600)
    log(domain, "→", ip, "(Cloudflare)")


def cf_forget(path, keep=""):
    """Removes the records the box made under an earlier Cloudflare name (best effort), and that name.
    Not those of `keep`, the name in use (signing in again keeps the same name)."""
    try:
        c = json.loads(read(path, "{}") or "{}")
    except json.JSONDecodeError:
        c = {}
    if c.get("zone_id") and f"{c.get('sub')}.{c.get('zone')}" != keep:
        try:
            token = cf_token(c) if path == CF_FILE else (c.get("token") or c.get("access_token"))
            domain = f"{c['sub']}.{c['zone']}"
            for name in (domain, "*." + domain):
                out = cf(f"/zones/{c['zone_id']}/dns_records?name={urllib.parse.quote(name)}", token)
                for r in out.get("result", []):
                    if (r.get("comment") or "") == RECORD_COMMENT:
                        cf(f"/zones/{c['zone_id']}/dns_records/{r['id']}", token, "DELETE")
            log("removed", domain, "from Cloudflare")
        except (RuntimeError, SignIn, urllib.error.URLError, OSError, KeyError) as e:
            log("couldn't remove the old Cloudflare records:", e)
    for f in (path, CF_SENT) if path == CF_FILE else (path,):
        if os.path.exists(f):
            os.remove(f)


def pocket_forget():
    """Gives Pocket's free address back once the box no longer uses it (best effort)."""
    if not os.path.exists(ACCOUNT):
        return
    try:
        api("DELETE", "/v1/box", None, json.load(open(ACCOUNT)))
        log("gave the Pocket name back")
    except (RuntimeError, Rejected, Waiting, Limited, urllib.error.URLError, OSError) as e:
        log("couldn't give the Pocket name back now:", e)
        return
    for f in (ACCOUNT, SENT):
        if os.path.exists(f):
            os.remove(f)


def choice():
    fw = read(FW_CFG).strip()
    if fw == "off":
        return "off"
    try:
        mode = json.loads(read(CHOICE, "{}") or "{}").get("mode")
    except json.JSONDecodeError:
        mode = None
    if mode in ("pocket", "cloudflare", "own-ca"):
        return mode
    # Boxes that got their Pocket name before there was a choice keep it; tests can pick it up front.
    if os.path.exists(ACCOUNT) or os.path.exists(DOMAIN_FILE) or fw == "pocket":
        write(CHOICE, json.dumps({"mode": "pocket", "at": int(time.time()), "by": "box"}))
        return "pocket"
    return None


def run_pocket():
    acct = account()
    try:
        send_address(acct)
    except Rejected:
        # The name was given back (unused for months, or removed by hand): start over with a new one.
        log("Pocket Names no longer knows", acct["domain"], "- registering again")
        os.remove(ACCOUNT)
        for f in (SENT,):
            if os.path.exists(f):
                os.remove(f)
        acct = account()
        send_address(acct)
    domain = acct["domain"]
    if not cert_ok(domain):
        status("certificate")
        get_cert(domain, "httpreq", pocket_cert_env(acct))
    if cert_ok(domain, days=0):
        if install(domain):
            switch_apps()
        status("ready")
        if os.path.exists(CF_FILE):
            cf_forget(CF_FILE)
        if os.path.exists(CF_OLD):
            cf_forget(CF_OLD)


def run_cloudflare():
    c = json.load(open(CF_FILE))
    domain = f"{c['sub']}.{c['zone']}"
    token = cf_token(c)
    ip = home_address()
    if ip:
        cf_point(c, token, ip)
    elif read(DOMAIN_FILE).strip() != domain:
        raise RuntimeError("no home-network IPv4 address to point the name at yet")
    if not cert_ok(domain):
        status("certificate")
        get_cert(domain, "cloudflare", {"CF_DNS_API_TOKEN": token, "CF_ZONE_API_TOKEN": token})
    if cert_ok(domain, days=0):
        if install(domain):
            switch_apps()
        status("ready")
        pocket_forget()
        if os.path.exists(CF_OLD):
            cf_forget(CF_OLD, keep=domain)


def run_own_ca():
    if os.path.exists(DOMAIN_FILE):
        uninstall()
        switch_apps()
    pocket_forget()
    for f in (CF_FILE, CF_OLD):
        if os.path.exists(f):
            cf_forget(f)
    status("own-ca")


def main():
    mode = choice()
    if mode == "off":
        log("public name turned off for this machine (fw_cfg)")
        status("off")
        return
    os.makedirs(PRIVATE, exist_ok=True)
    os.chmod(PRIVATE, 0o700)
    os.chmod(STATE, 0o755)
    lock = open(os.path.join(PRIVATE, "lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("already running")
        return
    if mode is None:
        status("choose")
        log("waiting for the owner to choose how the box gets its address")
        return
    try:
        if mode != "own-ca" and not os.path.exists(os.path.join(STATE, "public", "name-status.json")):
            status("asking")  # only the first time: later runs keep the last outcome until they have a new one
        if mode == "pocket":
            run_pocket()
        elif mode == "cloudflare":
            run_cloudflare()
        else:
            run_own_ca()
        problem()
        write_etc_hosts()
    except SignIn as e:
        log("not this time:", e)
        msg = "The box's Cloudflare sign-in stopped working. Sign in again in Pocket Core → Settings → This box."
        status("signin", msg)
        problem("signin", msg)
        if os.path.exists(DOMAIN_FILE):
            write_etc_hosts()
    except (RuntimeError, urllib.error.URLError, OSError, subprocess.TimeoutExpired, Rejected, Waiting, Limited, KeyError, ValueError) as e:
        # No internet, Pocket Names or Cloudflare down or holding the box back, Let's Encrypt busy: the
        # box keeps working on its current address and a timer tries again.
        log("not this time:", e)
        if isinstance(e, Limited):
            status("limited", str(e))
            problem("limited", str(e))
        elif isinstance(e, Waiting):
            status("waiting", "Pocket Names hasn't let this box in yet; it asks again every few minutes.")
        elif isinstance(e, urllib.error.URLError) and not isinstance(e, urllib.error.HTTPError):
            status("offline", "The box can't reach the internet yet.")
        else:
            status("failed", "Getting the name didn't work this time; the box tries again in a few minutes.")
        if not isinstance(e, Limited):
            problem("failed", str(e)[:300])
        if os.path.exists(DOMAIN_FILE):
            write_etc_hosts()


main()
