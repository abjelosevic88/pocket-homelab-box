"""pocket-box-update: move the box to the newest release, keep it only if it is healthy.

1. Build (or download from the cache) this box's system from the release flake.
2. Same as the running one: nothing to do. A release that failed here before: skipped.
3. Switch to it, then wait for every Pocket app and service to answer.
4. Healthy: done (a new kernel waits for the next restart; the nightly run restarts the box).
   Not healthy: switch back to the previous system and remember the release as bad.

State in STATE (/var/lib/pocket-box/update): status.json (what the last run did), bad (releases
that failed), auto-off (no nightly updates), manual (this run was asked for in Settings), flake
(an override of the release flake, for support and tests).
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

CONFIG = json.load(open(sys.argv[1]))
STATE = CONFIG["state_dir"]
PROFILE = "/nix/var/nix/profiles/system"


def path(name):
    return os.path.join(STATE, name)


def release(system):
    try:
        return json.load(open(os.path.join(system, "etc", "pocket-box", "release.json")))
    except (OSError, ValueError):
        return {}


def write_status(result, message, **extra):
    st = {"result": result, "message": message, "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
          "current": release("/run/current-system"), **extra}
    tmp = path("status.json.tmp")
    with open(tmp, "w") as f:
        json.dump(st, f)
    os.replace(tmp, path("status.json"))
    print(result, "-", message, flush=True)


def run(*args, timeout=None):
    r = subprocess.run(list(args), capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout).strip()[-1500:])
    return r.stdout.strip()


def healthy(deadline):
    """Every Pocket app answers /healthz and no Pocket unit failed; returns what is still wrong."""
    wrong = []
    while time.time() < deadline:
        wrong = []
        for name, url in CONFIG["checks"].items():
            try:
                with urllib.request.urlopen(url, timeout=5) as r:
                    if r.status != 200:
                        wrong.append(name)
            except Exception:
                wrong.append(name)
        failed = subprocess.run([CONFIG["systemctl"], "list-units", "--failed", "--plain", "--no-legend", "pocket-*"],
                                capture_output=True, text=True).stdout.split()
        wrong += [u for u in failed if u.endswith(".service")]
        if not wrong:
            return []
        time.sleep(10)
    return wrong


def switch(system):
    run(CONFIG["nix-env"], "-p", PROFILE, "--set", system)
    run(os.path.join(system, "bin", "switch-to-configuration"), "switch", timeout=1800)


def main():
    os.makedirs(STATE, exist_ok=True)
    manual = os.path.exists(path("manual"))
    if manual:
        os.remove(path("manual"))
    if not manual and os.path.exists(path("auto-off")):
        write_status("paused", "Automatic updates are off.")
        return 0
    flake = open(path("flake")).read().strip() if os.path.exists(path("flake")) else CONFIG["flake"]
    write_status("checking", "Looking for a new release…")
    target = f"{flake}#nixosConfigurations.{CONFIG['variant']}.config.system.build.toplevel"
    try:
        new = run(CONFIG["nix"], "build", "--no-link", "--print-out-paths", "--refresh", target, timeout=6 * 3600).splitlines()[-1]
    except (RuntimeError, subprocess.TimeoutExpired) as e:
        write_status("error", "Could not get the new release.", detail=str(e)[-800:])
        return 1
    current = os.path.realpath("/run/current-system")
    if new == current:
        write_status("up-to-date", "This is the newest release.")
        return 0
    bad = open(path("bad")).read().split() if os.path.exists(path("bad")) else []
    if new in bad:
        write_status("skipped", "The newest release failed on this box before; waiting for the next one.", available=release(new))
        return 0

    before = release(current)
    write_status("installing", "Installing the new release…", available=release(new))
    try:
        switch(new)
    except (RuntimeError, subprocess.TimeoutExpired) as e:
        # switch-to-configuration ends with "the following units failed: a.service, b.service".
        failed_units = re.findall(r"the following units failed: (.+)", str(e))
        wrong = [u.strip() for line in failed_units for u in line.split(",") if u.strip()] or [f"switch: {str(e)[-300:]}"]
    else:
        wrong = healthy(time.time() + CONFIG["health_seconds"])
    if wrong:
        with open(path("bad"), "a") as f:
            f.write(new + "\n")
        try:
            switch(current)
        except (RuntimeError, subprocess.TimeoutExpired) as e:
            write_status("error", "The new release failed and going back failed too.", failing=wrong, detail=str(e)[-800:])
            return 1
        write_status("rolled-back", "The new release did not start cleanly, so the box went back to the previous one.",
                     failing=wrong[:20], available=release(new))
        return 1

    kernel_changed = os.path.realpath(os.path.join(new, "kernel")) != os.path.realpath("/run/booted-system/kernel")
    write_status("updated", f"Updated from {before.get('version', '?')} to {release(new).get('version', '?')}.",
                 previous=before, restart_needed=kernel_changed)
    if kernel_changed and not manual:
        subprocess.run([CONFIG["systemctl"], "reboot"])
    return 0


sys.exit(main())
