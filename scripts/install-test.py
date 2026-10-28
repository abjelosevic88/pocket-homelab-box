"""Installs the Pocket Box ISO onto a blank virtual disk over the serial console, then boots the disk. Run via install-test.sh."""
import os, re, subprocess, sys, time, select, shutil, urllib.request

iso, ovmf, qemu, work = sys.argv[1:5]
os.makedirs(work, exist_ok=True)
disk = os.path.join(work, "disk.qcow2")
vars_fd = os.path.join(work, "vars.fd")
boot_only = os.environ.get("BOOT_ONLY") == "1"
if not boot_only and os.path.exists(disk): os.remove(disk)
if not boot_only: subprocess.run([f"{qemu}/bin/qemu-img", "create", "-q", "-f", "qcow2", disk, "32G"], check=True)
if not boot_only: shutil.copy(f"{ovmf}/FV/OVMF_VARS.fd", vars_fd); os.chmod(vars_fd, 0o644)
log = open(os.path.join(work, "serial-boot.log" if boot_only else "serial.log"), "wb")

def vm(extra):
    return subprocess.Popen([f"{qemu}/bin/qemu-system-x86_64", "-enable-kvm", "-m", "6144", "-smp", "4",
        "-drive", f"if=pflash,format=raw,readonly=on,file={ovmf}/FV/OVMF_CODE.fd",
        "-drive", f"if=pflash,format=raw,file={vars_fd}",
        "-drive", f"file={disk},if=virtio", "-display", "none", "-serial", "stdio", "-monitor", "none", *extra],
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
                buf = buf[buf.index(needle.encode()) + len(needle):]
                return True
    raise SystemExit(f"timeout waiting for {needle!r}")

def send(p, s): p.stdin.write(s.encode()); p.stdin.flush()

if not boot_only:
  print("phase 1: install from ISO", flush=True)
  p = vm(["-cdrom", iso, "-boot", "order=d", "-nic", "user,model=virtio-net-pci"])
  expect(p, "nixos@nixos", 300); time.sleep(2)
  send(p, "sudo pocket-install vda\n")
  expect(p, "Type the disk name again", 60)
  send(p, "vda\n")
  expect(p, "Done. Remove the USB stick", 2400)
  print("installed", flush=True)
  send(p, "sudo poweroff\n")
  end = time.time() + 120
  while p.poll() is None and time.time() < end:
      if select.select([p.stdout], [], [], 1)[0]:
          c = os.read(p.stdout.fileno(), 65536); log.write(c)
          if not c: break
  p.wait(timeout=30)

print("phase 2: boot installed disk", flush=True)
# The installed box serves https://<slug>.pocket.local on 443 and the landing page on 80; they are
# forwarded to host ports 28443/28080 and every name is resolved to 127.0.0.1 by curl.
catalog = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps.nix")).read()
slugs = re.findall(r"^  ([a-z]+) = \{\n    title", catalog, re.M)
sites = [(s, "/healthz") for s in slugs] + [("jellyfin", "/health"), ("navidrome", "/ping"), ("immich", "/api/server/ping"), ("onlyoffice", "/healthcheck")]
domain, https_port, http_port = "pocket.local", 28443, 28080
ca = os.path.join(work, "ca.crt")
p = vm(["-nic", f"user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:{https_port}-:443,hostfwd=tcp:127.0.0.1:{http_port}-:80"])


def drain_log():
    while select.select([p.stdout], [], [], 0)[0]:
        c = os.read(p.stdout.fileno(), 65536)
        log.write(c)
        if not c:
            break


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

failed = []
for name, path in sites:
    host = f"{name}.{domain}"
    for _ in range(40):
        r = curl("--cacert", ca, "--resolve", f"{host}:{https_port}:127.0.0.1", "-o", "/dev/null", "-w", "%{http_code}", f"https://{host}:{https_port}{path}")
        if r.stdout == "200":
            break
        time.sleep(3)
        drain_log()
    else:
        failed.append(name)
print(f"{len(sites) - len(failed)}/{len(sites)} sites healthy over verified https" + (f", failing: {failed}" if failed else ""), flush=True)
p.terminate()
p.wait()
sys.exit(1 if failed else 0)
