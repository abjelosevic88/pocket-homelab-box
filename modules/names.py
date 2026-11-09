"""pocket-box-name: the box's public name and a certificate every browser trusts.

Run by a timer. Each run:
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
"""
import base64
import ipaddress
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
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


def get_cert(acct):
    domain = acct["domain"]
    env = {"PATH": "/run/current-system/sw/bin", "HOME": PRIVATE,
           "HTTPREQ_ENDPOINT": CONFIG["server"] + "/acme",
           "HTTPREQ_USERNAME": acct["name"], "HTTPREQ_PASSWORD": acct["token"]}
    log("asking Let's Encrypt for a certificate for", domain, "and *." + domain)
    run(T["lego"], "--log.format", "text", "run", "--path", LEGO, "--server", CONFIG["acme_server"],
        # Let's Encrypt asks Cloudflare's own name servers, so that is the only propagation check: public
        # resolvers can remember "no such record" from before the challenge was made, and time out.
        "--accept-tos", "--dns", "httpreq", "--dns.resolvers", "1.1.1.1:53,8.8.8.8:53",
        "--dns.propagation.disable-rns",
        "--renew-days", "30", "--no-random-sleep",
        "-d", domain, "-d", "*." + domain, env=env, timeout=900)


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


def install(acct):
    """Hands the certificate to Caddy and switches the box over; returns whether the name is new."""
    domain = acct["domain"]
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


def write_etc_hosts():
    """/etc/hosts is a copy (environment.etc.hosts.mode); this adds the box's own public names to it."""
    if os.path.islink("/etc/hosts"):
        return
    text = read("/etc/static/hosts") + read(os.path.join(STATE, "hosts"))
    write("/etc/hosts", text)


def switch_apps():
    """The apps read their public URLs at start; restart them so they register under the new name.

    One queued job for all of them: systemd keeps the order (the media services' setup rewrites Core's
    service list before Core starts, Core before the apps) without this run waiting for it all."""
    log("restarting the apps on the new name")
    run(T["systemctl"], "restart", "--no-block", *CONFIG["backends_units"], *CONFIG["app_units"])


def main():
    if read(FW_CFG).strip() == "off":
        log("public name turned off for this machine (fw_cfg)")
        return
    os.makedirs(PRIVATE, exist_ok=True)
    os.chmod(PRIVATE, 0o700)
    os.chmod(STATE, 0o755)
    try:
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
        if not cert_ok(acct["domain"]):
            get_cert(acct)
        if cert_ok(acct["domain"], days=0):
            if install(acct):
                switch_apps()
        write_etc_hosts()
    except (RuntimeError, urllib.error.URLError, OSError, subprocess.TimeoutExpired, Rejected) as e:
        # No internet, Pocket Names down, Let's Encrypt busy: the box keeps working on pocket.local and
        # the timer tries again.
        log("not this time:", e)
        if os.path.exists(DOMAIN_FILE):
            write_etc_hosts()


main()
