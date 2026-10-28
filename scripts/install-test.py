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
# Every app in apps.nix, forwarded to host port +20000 (the box's own ports are often taken on a dev machine).
catalog = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps.nix")).read()
ports = [int(p) for p in re.findall(r"^    port = (\d+);", catalog, re.M)]
fwd = ",".join(f"hostfwd=tcp:127.0.0.1:{x+20000}-:{x}" for x in ports)
p = vm(["-nic", f"user,model=virtio-net-pci,{fwd}"])
end = time.time() + 300
while time.time() < end:
    select.select([p.stdout], [], [], 2)
    try:
        while select.select([p.stdout], [], [], 0)[0]:
            c = os.read(p.stdout.fileno(), 65536); log.write(c); log.flush()
            if not c: break
    except OSError: pass
    try:
        out = urllib.request.urlopen("http://127.0.0.1:28179/healthz", timeout=2).read().decode()
        print("core:", out, flush=True); break
    except Exception: pass
failed = []
for port in [x + 20000 for x in ports]:
    for _ in range(30):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=2); break
        except Exception:
            time.sleep(2)
            while select.select([p.stdout], [], [], 0)[0]:
                c = os.read(p.stdout.fileno(), 65536); log.write(c)
                if not c: break
    else:
        failed.append(port - 20000)
print(f"{len(ports) - len(failed)}/{len(ports)} apps healthy" + (f", failing ports: {failed}" if failed else ""), flush=True)
p.terminate(); p.wait()
sys.exit(1 if failed else 0)
