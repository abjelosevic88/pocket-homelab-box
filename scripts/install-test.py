"""Installs the Pocket Box ISO onto a blank virtual disk over the serial console, then boots the disk. Run via install-test.sh."""
import json, os, re, socket, subprocess, sys, threading, time, select, shutil, urllib.request

iso, ovmf, qemu, work = sys.argv[1:5]
os.makedirs(work, exist_ok=True)
disk = os.path.join(work, "disk.qcow2")
vars_fd = os.path.join(work, "vars.fd")
boot_only = os.environ.get("BOOT_ONLY") == "1"
if not boot_only and os.path.exists(disk): os.remove(disk)
if not boot_only: shutil.rmtree(os.path.join(work, "tpm"), ignore_errors=True)
if not boot_only: subprocess.run([f"{qemu}/bin/qemu-img", "create", "-q", "-f", "qcow2", disk, "32G"], check=True)
if not boot_only: shutil.copy(f"{ovmf}/FV/OVMF_VARS.fd", vars_fd); os.chmod(vars_fd, 0o644)
log = open(os.path.join(work, "serial-boot.log" if boot_only else "serial.log"), "wb")

qmp = os.path.join(work, "qmp.sock")


def power_down(p, seconds=180):
    """Press the virtual power button and wait for the box to shut down (a kill can lose writes)."""
    try:
        q = socket.socket(socket.AF_UNIX)
        q.connect(qmp)
        q.recv(4096)
        for cmd in ("qmp_capabilities", "system_powerdown"):
            q.sendall(json.dumps({"execute": cmd}).encode() + b"\n")
            time.sleep(0.5)
            q.recv(4096)
        q.close()
        p.wait(timeout=seconds)
    except (OSError, subprocess.TimeoutExpired):
        p.terminate()
        p.wait()


use_tpm = os.environ.get("TPM", "1") != "0"
tpm_dir = os.path.join(work, "tpm")
tpm_sock = os.path.join(work, "swtpm.sock")


def start_tpm():
    """A software TPM 2.0 for the VM; its state lives in WORK/tpm across boots, like a real chip."""
    if not use_tpm:
        return []
    os.makedirs(tpm_dir, exist_ok=True)
    if os.path.exists(tpm_sock):
        os.remove(tpm_sock)
    subprocess.Popen([os.environ["SWTPM"], "socket", "--tpmstate", f"dir={tpm_dir}", "--ctrl", f"type=unixio,path={tpm_sock}",
                      "--tpm2", "--flags", "startup-clear"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        if os.path.exists(tpm_sock):
            break
        time.sleep(0.1)
    return ["-chardev", f"socket,id=chrtpm,path={tpm_sock}", "-tpmdev", "emulator,id=tpm0,chardev=chrtpm", "-device", "tpm-crb,tpmdev=tpm0"]


def vm(extra):
    return subprocess.Popen([f"{qemu}/bin/qemu-system-x86_64", "-enable-kvm", "-m", "6144", "-smp", "4",
        "-drive", f"if=pflash,format=raw,readonly=on,file={ovmf}/FV/OVMF_CODE.fd",
        "-drive", f"if=pflash,format=raw,file={vars_fd}",
        "-drive", f"file={disk},if=virtio", "-display", "none", "-serial", "stdio", "-monitor", "none",
        "-qmp", f"unix:{qmp},server,nowait", *start_tpm(), *extra],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

buf = b""
def expect(p, needle, timeout):
    global buf
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 1)
        if r:
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk: break
            buf += chunk; log.write(chunk); log.flush()
            if needle.encode() in buf:
                cut = buf.index(needle.encode()) + len(needle)
                seen, buf = buf[:cut], buf[cut:]
                return seen
    raise SystemExit(f"timeout waiting for {needle!r}")

def send(p, s): p.stdin.write(s.encode()); p.stdin.flush()

if not boot_only:
  print("phase 1: install from ISO", flush=True)
  p = vm(["-cdrom", iso, "-boot", "order=d", "-nic", "user,model=virtio-net-pci"])
  expect(p, "nixos@nixos", 300); time.sleep(2)
  send(p, "sudo pocket-install vda\n")
  expect(p, "Type the disk name again", 60)
  send(p, "vda\n")
  if use_tpm:
      seen = expect(p, "Press Enter once", 2400)
      if not re.search(rb"([cbdefghijklnrtuv]{8}-){7}[cbdefghijklnrtuv]{8}", seen):
          raise SystemExit("the installer showed no recovery key")
      send(p, "\n")
      print("encrypted; recovery key shown", flush=True)
  expect(p, "Done. Remove the USB stick", 2400)
  print("installed", flush=True)
  send(p, "sudo sync; sudo poweroff\n")
  end = time.time() + 180
  while p.poll() is None and time.time() < end:
      if select.select([p.stdout], [], [], 1)[0]:
          c = os.read(p.stdout.fileno(), 65536); log.write(c)
          if not c: break
  if p.poll() is None:
      # The disk is installed and synced; a slow shutdown is the installer's business.
      print("installer slow to power off; pressing the power button", flush=True)
      power_down(p, 60)

print("phase 2: boot installed disk", flush=True)
# The installed box serves https://<slug>.pocket.local on 443 and the landing page on 80; they are
# forwarded to host ports 28443/28080 and every name is resolved to 127.0.0.1 by curl.
catalog = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps.nix")).read()
slugs = re.findall(r"^  ([a-z]+) = \{\n    title", catalog, re.M)
sites = [(s, "/healthz") for s in slugs] + [("jellyfin", "/health"), ("navidrome", "/ping"), ("immich", "/api/server/ping"), ("onlyoffice", "/healthcheck")]
domain, https_port, http_port = "pocket.local", 28443, 28080
ca = os.path.join(work, "ca.crt")
p = vm(["-nic", f"user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:{https_port}-:443,hostfwd=tcp:127.0.0.1:{http_port}-:80"])


def pump():
    # Read the serial console all the time: a full pipe would block qemu, and with it the disk.
    while True:
        c = os.read(p.stdout.fileno(), 65536)
        if not c:
            return
        log.write(c)
        log.flush()


threading.Thread(target=pump, daemon=True).start()


def drain_log():
    pass


def curl(*args):
    return subprocess.run(["curl", "-s", "-m", "8", *args], capture_output=True, text=True)


end = time.time() + 400
while time.time() < end:
    drain_log()
    if curl("-f", "-o", ca, "--resolve", f"{domain}:{http_port}:127.0.0.1", f"http://{domain}:{http_port}/pocket-box-ca.crt").returncode == 0:
        print("landing page up, certificate downloaded", flush=True)
        break
    time.sleep(3)
else:
    raise SystemExit("landing page never came up")

pending = dict(sites)
end = time.time() + 600
while pending and time.time() < end:
    for name, path in list(pending.items()):
        host = f"{name}.{domain}"
        r = curl("--cacert", ca, "--resolve", f"{host}:{https_port}:127.0.0.1", "-o", "/dev/null", "-w", "%{http_code}", f"https://{host}:{https_port}{path}")
        if r.stdout == "200":
            del pending[name]
    drain_log()
    if pending:
        time.sleep(5)
failed = list(pending)
print(f"{len(sites) - len(failed)}/{len(sites)} sites healthy over verified https" + (f", failing: {failed}" if failed else ""), flush=True)

# The owner's first run: an account in Core, their own accounts in the media services, and the
# apps on top of those services connected as them through "Sign in with Pocket Core".
jar = os.path.join(work, "owner.jar")
if os.path.exists(jar):
    os.remove(jar)


def https(name, path, *args):
    # The box's own URLs carry no port (sign-in redirects between apps and Core): send every
    # name and port to the forwarded https port.
    return curl("-m", "30", "--cacert", ca, "--connect-to", f"::127.0.0.1:{https_port}",
                "-b", jar, "-c", jar, *args, f"https://{name}.{domain}{path}")


owner = {"email": "owner@example.com", "password": "install-test-1", "name": "Owner"}
r = https("core", "/api/v1/auth/setup", "-H", "Content-Type: application/json", "-d", json.dumps(owner))
if "setup already completed" in r.stdout:  # BOOT_ONLY=1 on a box whose owner exists
    r = https("core", "/api/v1/auth/login", "-H", "Content-Type: application/json", "-d", json.dumps(owner))
if '"owner@example.com"' not in r.stdout:
    failed.append("core setup")
    print("core setup:", r.stdout[:200], flush=True)
backends = {"jellyfin": "watch", "navidrome": "music", "immich": "photos"}
accounts = {}
end = time.time() + 300
while time.time() < end and len(accounts) < len(backends):
    drain_log()
    try:
        services = json.loads(https("core", "/api/v1/services").stdout or "[]")
    except ValueError:
        services = []
    for sv in services:
        if sv.get("type") in backends and sv["type"] not in accounts:
            try:
                rows = json.loads(https("core", f"/api/v1/services/{sv['id']}/connector/accounts").stdout or "[]")
            except ValueError:
                rows = []
            if any(a.get("status") == "ok" for a in rows):
                accounts[sv["type"]] = True
    time.sleep(5)
for backend, app in backends.items():
    if backend not in accounts:
        failed.append(f"{backend} account")
        continue
    https(app, "/api/v1/auth/oidc/start", "-L", "-o", "/dev/null")
    try:
        conn = json.loads(https(app, "/api/v1/connection").stdout or "{}")
    except ValueError:
        conn = {}
    if conn.get("connected") is not True:
        failed.append(f"{app} → {backend}")
        print(f"{app} connection:", json.dumps(conn)[:300], flush=True)
# The setup wizard, through Core: time zone and console password, the disk as installed, done.
def api(method, path, body=None):
    args = ["-X", method, "-H", "Content-Type: application/json"] + (["-d", json.dumps(body)] if body is not None else [])
    try:
        return json.loads(https("core", "/api/v1" + path, *args).stdout or "{}")
    except ValueError:
        return {}


st = api("GET", "/auth/status")
if st.get("box_wizard") is not True and not os.environ.get("BOOT_ONLY"):
    failed.append("wizard not offered")
if api("PUT", "/box/system/timezone", {"timezone": "Europe/Sarajevo"}).get("timezone") != "Europe/Sarajevo":
    failed.append("time zone")
if api("PUT", "/box/system/password", {"password": "console-pass-1"}).get("password_set") is not True:
    failed.append("console password")
disk = api("GET", "/box/system/status").get("encryption", {})
if disk.get("encrypted") is not use_tpm or disk.get("tpm") is not use_tpm or disk.get("recovery_key") is not use_tpm:
    failed.append(f"disk {disk}")
api("POST", "/box/system/wizard", {})
if api("GET", "/auth/status").get("box_wizard") is not False:
    failed.append("wizard still pending")
print(f"wizard: time zone, console password, disk {'encrypted with TPM unlock' if disk.get('tpm') else 'plain'}", flush=True)
print("owner's accounts: " + ", ".join(sorted(accounts)) + "; apps connected: "
      + ", ".join(a for b, a in backends.items() if f"{a} → {b}" not in failed and b in accounts), flush=True)
power_down(p)
sys.exit(1 if failed else 0)
