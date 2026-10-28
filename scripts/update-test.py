"""Updates with rollback, on the disk install-test.py left behind (run that first).

The host serves two copies of this flake to the box (http://10.0.2.2 inside the VM):
  good  adds /etc/pocket-box/update-test       → the box must install it and stay healthy
  bad   also makes Pocket Habits fail to start → the box must go back to "good" by itself
Each is handed to pocket-box-update through its override file, over the serial console as the
console user (password set by install-test's wizard step).
"""
import functools
import http.server
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tarfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ovmf, qemu, work = sys.argv[1:4]
disk, vars_fd = os.path.join(work, "disk.qcow2"), os.path.join(work, "vars.fd")
serial, qmp, tpm_dir, tpm_sock = (os.path.join(work, n) for n in ("update-serial.sock", "update-qmp.sock", "tpm", "swtpm.sock"))
PASSWORD = "console-pass-1"
if not os.path.exists(disk):
    raise SystemExit("no installed disk: run scripts/install-test.sh first")

# ---- the two releases ----
site = os.path.join(work, "releases")
shutil.rmtree(site, ignore_errors=True)
os.makedirs(site)
files = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
EXTRA = {
    "good": 'environment.etc."pocket-box/update-test".text = "good";',
    "bad": 'environment.etc."pocket-box/update-test".text = "good";\n'
           '  systemd.services.pocket-habits.serviceConfig.ExecStart = lib.mkForce "/run/current-system/sw/bin/false";',
}
for name, extra in EXTRA.items():
    with tarfile.open(os.path.join(site, f"{name}.tar.gz"), "w:gz") as tar:
        for f in files:
            src = os.path.join(ROOT, f)
            if not os.path.isfile(src):
                continue
            if f == "hosts/box.nix":
                text = open(src).read()
                text = text[:text.rindex("}")] + "  " + extra + "\n}\n"
                data = text.encode()
                info = tarfile.TarInfo(f"pocket-box/{f}")
                info.size, info.mtime = len(data), int(time.time())
                tar.addfile(info, fileobj=__import__("io").BytesIO(data))
            else:
                tar.add(src, arcname=f"pocket-box/{f}")
httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(http.server.SimpleHTTPRequestHandler, directory=site))
port = httpd.server_address[1]
threading.Thread(target=httpd.serve_forever, daemon=True).start()

# ---- the box ----
for s in (serial, qmp, tpm_sock):
    if os.path.exists(s):
        os.remove(s)
tpm = []
if os.path.isdir(tpm_dir):
    subprocess.Popen([os.environ["SWTPM"], "socket", "--tpmstate", f"dir={tpm_dir}", "--ctrl", f"type=unixio,path={tpm_sock}", "--tpm2",
                      "--flags", "startup-clear"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    while not os.path.exists(tpm_sock):
        time.sleep(0.1)
    tpm = ["-chardev", f"socket,id=chrtpm,path={tpm_sock}", "-tpmdev", "emulator,id=tpm0,chardev=chrtpm", "-device", "tpm-crb,tpmdev=tpm0"]
vm = subprocess.Popen([f"{qemu}/bin/qemu-system-x86_64", "-enable-kvm", "-m", "6144", "-smp", "4",
                       "-drive", f"if=pflash,format=raw,readonly=on,file={ovmf}/FV/OVMF_CODE.fd", "-drive", f"if=pflash,format=raw,file={vars_fd}",
                       "-drive", f"file={disk},if=virtio", "-display", "none", "-monitor", "none",
                       "-serial", f"unix:{serial},server,nowait", "-qmp", f"unix:{qmp},server,nowait", *tpm,
                       "-nic", "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:28443-:443"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
while not os.path.exists(serial):
    time.sleep(0.2)
con = socket.socket(socket.AF_UNIX)
con.connect(serial)
con.settimeout(0.5)


def drain(secs, stop=None):
    out, end = b"", time.time() + secs
    while time.time() < end:
        try:
            c = con.recv(65536)
            if c:
                out += c
        except socket.timeout:
            pass
        if stop and stop in out:
            break
    return out.decode(errors="replace")


def sh(cmd, secs=120):
    mark = f"__END{time.time_ns()}__"
    con.sendall(f"echo {PASSWORD} | sudo -S -p '' sh -c {json.dumps(cmd)} 2>&1; echo {mark}\n".encode())
    out = drain(secs, (mark + "\r\n").encode())
    return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\r", "", out).split(mark)[0].strip()


def healthz(name):
    r = subprocess.run(["curl", "-sk", "-m", "8", "--connect-to", "::127.0.0.1:28443", "-o", "/dev/null", "-w", "%{http_code}",
                        f"https://{name}.pocket.local/healthz"], capture_output=True, text=True)
    return r.stdout == "200"


def update(release):
    sh(f"echo tarball+http://10.0.2.2:{port}/{release}.tar.gz > /var/lib/pocket-box/update/flake; touch /var/lib/pocket-box/update/manual; systemctl start --no-block pocket-box-update.service")
    end = time.time() + 3600
    time.sleep(10)
    while time.time() < end:
        # The console prompt sticks to the answer ("$ activating"), so look for the word.
        if "activating" not in sh("systemctl is-active pocket-box-update.service", 30):
            break
        time.sleep(20)
    raw = sh("cat /var/lib/pocket-box/update/status.json")
    a, b = raw.find("{"), raw.rfind("}")
    try:
        return json.loads(raw[a:b + 1])
    except ValueError:
        print("unreadable status:", repr(raw[-600:]), flush=True)
        print(sh("journalctl -u pocket-box-update -n 25 --no-pager -o cat"), flush=True)
        return {}


failed = []
try:
    print("booting the installed box", flush=True)
    end = time.time() + 600
    while time.time() < end and not healthz("core"):
        time.sleep(5)
    con.sendall(b"\n")
    drain(4, b"login: ")
    con.sendall(b"pocket\n")
    drain(5, b"Password: ")
    con.sendall(PASSWORD.encode() + b"\n")
    if "pocket@pocket" not in drain(10, b"$ "):
        raise SystemExit("console login failed")
    con.sendall(b"export TERM=dumb SYSTEMD_PAGER=cat PS1='$ '; stty cols 250 -echo\n")
    drain(3)

    st = update("good")
    marker = sh("cat /etc/pocket-box/update-test")
    print("good release:", st.get("result"), "-", st.get("message"), "| marker:", marker.splitlines()[-1:], flush=True)
    # A re-run on the same disk finds "good" already installed.
    if st.get("result") not in ("updated", "up-to-date") or not marker.endswith("good"):
        failed.append(f"good: {st}")
    good_system = sh("readlink -f /run/current-system").splitlines()[-1]

    st = update("bad")
    now = sh("readlink -f /run/current-system").splitlines()[-1]
    print("bad release:", st.get("result"), "| failing:", st.get("failing"), "| back on good:", now == good_system, flush=True)
    if st.get("result") != "rolled-back" or now != good_system or not any("habits" in f for f in st.get("failing") or []):
        failed.append(f"bad: {st}")
    if not healthz("habits"):
        failed.append("habits not healthy after rolling back")
    st = update("bad")
    print("bad release again:", st.get("result"), flush=True)
    if st.get("result") != "skipped":
        failed.append(f"bad again: {st}")
finally:
    try:
        q = socket.socket(socket.AF_UNIX)
        q.connect(qmp)
        q.recv(4096)
        for cmd in ("qmp_capabilities", "system_powerdown"):
            q.sendall(json.dumps({"execute": cmd}).encode() + b"\n")
            time.sleep(0.5)
            q.recv(4096)
        vm.wait(timeout=180)
    except Exception:
        vm.terminate()
        vm.wait()
    httpd.shutdown()

print("update test:", "passed" if not failed else f"FAILED {failed}", flush=True)
sys.exit(1 if failed else 0)
