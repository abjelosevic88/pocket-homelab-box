"""pocket-box-screen: what the box's own screen shows above the login prompt.

The address to open on a phone or laptop (the public name once the box has it, else pocket.local), a
QR code for it, and how the console login works: user "pocket", and whether a console password is set
(never the password). Written to /run/pocket-box-screen/screen.issue, which /etc/issue.d links to;
agetty is told to show it again whenever it changes.
"""
import json
import os
import subprocess
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
    also = "  (it gets a secure address of its own within a few minutes)"

password_set = os.path.exists(CONFIG["password_flag"])
lines = [
    "",
    "  Pocket Box is ready. Open it on a phone or laptop on the same network:",
    "",
    f"    {address}",
    also,
    "",
]
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
