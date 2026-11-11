"""pocket-box-screen: what the box's own screen shows above the login prompt.

The address to open on a phone or laptop (the public name once the box has it, else pocket.local), a
QR code for it, and how the console login works: user "pocket", and whether a console password is set
(never the password). Written to /run/pocket-box-screen/screen.issue, which /etc/issue.d links to;
agetty is told to show it again whenever it changes.
"""
import json
import os
import subprocess
import time
import sys

CONFIG = json.load(open(sys.argv[1]))
OUT = CONFIG["out"]


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except FileNotFoundError:
        return ""


def qr(text):
    r = subprocess.run([CONFIG["qrencode"], "-t", "ANSIUTF8", "-m", "2", text], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


name = read(CONFIG["name_file"])
if name:
    address = f"https://core.{name}"
    scan = f"https://{name}"  # shorter, so the code stays small; it opens Pocket Core
    also = f"  (on this network also {CONFIG['landing']})"
else:
    address = CONFIG["landing"]
    scan = address
    # Before the owner chose how the box gets its padlock, that page asks; with the box's own
    # certificate it stays the address.
    try:
        mode = json.loads(read(CONFIG["choice_file"]) or "{}").get("mode")
    except ValueError:
        mode = None
    if mode == "own-ca":
        also = "  (install the box's certificate from that page once on each device)"
    elif mode:
        also = "  (it moves on to the box's secure address by itself)"
    else:
        also = "  (that page asks how the box gets its secure address)"

password_set = os.path.exists(CONFIG["password_flag"])

# Apps the box is still fetching (a Lite box's first boot, or Core's Install): pocket-box-apply's progress.
installing = ""
try:
    st = json.loads(read(CONFIG.get("apply_status", "")) or "{}")
except ValueError:
    st = {}
if st.get("state") in ("downloading", "switching", "starting") and time.time() - st.get("at", 0) < 3 * 3600:
    installing = f"  Installing your apps: {st.get('message', '')}. They show up in Pocket Core as they start."

lines = [
    "",
    "  Pocket Box is ready. Open it on a phone or laptop on the same network:",
    "",
    f"    {address}",
    also,
    "",
] + ([installing, ""] if installing else [])
code = qr(scan)
if code:
    lines += ["  Or scan this with your phone's camera:", ""] + ["  " + line for line in code.rstrip("\n").split("\n")] + [""]
lines += ["  Login on this screen (only for repairs; not your Pocket account):",
          "    user:      pocket"]
if password_set:
    lines += ["    password:  the console password set in Pocket Core",
              "               (Settings > System > Console password)"]
else:
    lines += ["    password:  none yet, so this login is locked. If you need it, set one in",
              "               Pocket Core: Settings > System > Console password"]
lines += ["", ""]
# agetty reads backslashes as escapes (\n is the host name, and so on).
text = "\n".join(lines).replace("\\", "\\\\")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
old = read(OUT)
if old != text.strip():
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, OUT)
    subprocess.run([CONFIG["agetty"], "--reload"], capture_output=True)
    print("screen updated:", address, "password set" if password_set else "console locked", flush=True)
