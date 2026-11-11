"""pocket-box-update: move the box to the newest release, keep it only if it is healthy.

1. Build (or download from the cache) this box's system from the release flake.
2. Same as the running one: nothing to do. A release that failed here before: skipped.
3. Switch to it, then wait for every Pocket app and service to answer.
4. Healthy: done (a new kernel waits for the next restart; the nightly run restarts the box).
   Not healthy: switch back to the previous system and remember the release as bad.

State in STATE (/var/lib/pocket-box/update): status.json (what the last run did), bad (releases
that failed), auto-off (no nightly updates), manual (this run was asked for in Settings), flake
(an override of the release flake, for support and tests).

A box that chose its apps keeps the list in /var/lib/pocket-box/apps.json ({"apps": [...]}); then the
update builds exactly those (the flake's lib.boxToplevel) instead of every app. `--apply` adds the
chosen apps this system doesn't carry yet, from this same release (its full revision in release.json),
for Core's Install and the first boot of a Lite box; its progress goes to update/apply.log too.
"""
import fcntl
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


def selection():
    """The apps this box chose, or None for "every app the release has"."""
    try:
        apps = json.load(open(CONFIG["selection"])).get("apps")
    except (OSError, ValueError, AttributeError):
        return None
    return [a for a in apps if isinstance(a, str)] if isinstance(apps, list) else None


def build_args(flake):
    if selection() is None:
        return [f"{flake}#nixosConfigurations.{CONFIG['variant']}.config.system.build.toplevel"]
    expr = (f'(builtins.getFlake "{flake}").lib.boxToplevel {{ variant = "{CONFIG["variant"]}"; '
            f'apps = (builtins.fromJSON (builtins.readFile {CONFIG["selection"]})).apps; }}')
    return ["--impure", "--expr", expr]


def lock():
    """One update or Install at a time."""
    f = open(path("lock"), "w")
    fcntl.flock(f, fcntl.LOCK_EX)
    return f


def run(*args, timeout=None):
    r = subprocess.run(list(args), capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout).strip()[-1500:])
    return r.stdout.strip()


def healthy(deadline):
    """Every installed Pocket app answers /healthz and no Pocket unit failed; returns what is still wrong."""
    wrong = []
    while time.time() < deadline:
        wrong = []
        for name, url in CONFIG["checks"].items():
            # An app removed in Core (no marker, see modules/installer.py) does not run, on purpose.
            if name != "core" and not os.path.exists(os.path.join(CONFIG["markers"], name)):
                continue
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
    try:
        new = run(CONFIG["nix"], "build", "--no-link", "--print-out-paths", "--refresh", *build_args(flake), timeout=6 * 3600).splitlines()[-1]
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


def say(msg):
    print(msg, flush=True)
    with open(path("apply.log"), "a") as f:
        f.write(msg + "\n")


def systemctl(*args):
    return subprocess.run([CONFIG["systemctl"], *args], capture_output=True, text=True)


def start_chosen(apps):
    """Each chosen app the system carries gets its marker and runs."""
    os.makedirs(CONFIG["markers"], exist_ok=True)
    for a in apps:
        open(os.path.join(CONFIG["markers"], a), "a").close()
        if systemctl("is-active", "--quiet", f"pocket-{a}.service").returncode != 0:
            systemctl("start", "--no-block", f"pocket-{a}.service")


def progress(state, apps, message, running=0):
    """update/apply.json, for the box's screen and Core's app store: installing which apps, how far."""
    st = {"state": state, "apps": apps, "message": message, "running": running, "total": len(apps),
          "at": int(time.time())}
    with open(path("apply.json.tmp"), "w") as f:
        json.dump(st, f)
    os.replace(path("apply.json.tmp"), path("apply.json"))
    subprocess.run([CONFIG["systemctl"], "start", "--no-block", "pocket-box-screen.service"], capture_output=True)


def uncached(args):
    """Whether building this would compile Pocket apps on the box: their builds are no longer in the cache
    (an old release; Cachix keeps only so much)."""
    r = subprocess.run([CONFIG["nix"], "build", "--dry-run", "--no-link", *args], capture_output=True, text=True, timeout=1800)
    out = r.stdout + r.stderr
    if "will be built" not in out:
        return False
    built = out.split("will be built", 1)[1].split("will be fetched", 1)[0]
    # An app's own build (pocket-<slug>-<version>, its -web-, -go-modules, -npm-deps), not the box's
    # small per-box files (pocket-box-*) or the system itself (nixos-system-pocket-…).
    return bool(re.search(r"/nix/store/[a-z0-9]{32}-(?!pocket-box)pocket-[a-z0-9-]+-\d[^/\s]*\.drv", built))


def apply():
    chosen = selection()
    if chosen is None:
        return 0
    cur = release("/run/current-system")
    have = set(cur.get("apps", []))
    missing = [a for a in chosen if a not in have]
    if not missing:
        start_chosen([a for a in chosen if a in have])
        return 0
    rev = cur.get("flake_rev", "")
    base = CONFIG["flake"]
    if os.path.exists(path("flake")):  # support and tests, as for the update
        flake = open(path("flake")).read().strip()
    elif rev and base.startswith("github:"):
        flake = "github:" + "/".join(base[len("github:"):].split("/")[:2]) + "/" + rev
    else:
        say("This box's system was not built from a release, so it can't add apps.")
        progress("failed", missing, "This box's system was not built from a release, so it can't add apps.")
        return 1
    n = len(missing)
    some = f"{n} app{'s' if n > 1 else ''}"
    say(f"Getting {some} for this box: {', '.join(missing)}")
    progress("downloading", missing, f"Downloading {some} (a few minutes)")
    try:
        if flake != base and not os.path.exists(path("flake")) and uncached(build_args(flake)):
            # This release's apps are gone from the cache: take the newest release instead, which also
            # updates the box (the same as tonight's update would).
            say("This box's release is no longer in the download cache; getting the apps from the newest release, which updates the box too")
            flake = base
        new = run(CONFIG["nix"], "build", "--no-link", "--print-out-paths", "--refresh", *build_args(flake), timeout=3 * 3600).splitlines()[-1]
    except (RuntimeError, subprocess.TimeoutExpired) as e:
        say("Downloading them did not work: " + str(e)[-400:])
        progress("failed", missing, "Downloading them did not work; the box tries again in a while.")
        return 1
    current = os.path.realpath("/run/current-system")
    say("Downloaded; switching the box over")
    progress("switching", missing, "Downloaded; switching the box over")
    try:
        switch(new)
        wrong = healthy(time.time() + CONFIG["health_seconds"])
    except (RuntimeError, subprocess.TimeoutExpired) as e:
        wrong = [f"switch: {str(e)[-300:]}"]
    if wrong:
        say("The box did not come back cleanly (" + ", ".join(wrong[:5]) + "), so it went back")
        try:
            switch(current)
        except (RuntimeError, subprocess.TimeoutExpired):
            pass
        keep = [a for a in chosen if a not in missing]
        with open(CONFIG["selection"] + ".tmp", "w") as f:
            json.dump({"apps": keep}, f)
        os.replace(CONFIG["selection"] + ".tmp", CONFIG["selection"])
        progress("failed", missing, "The box did not come back cleanly with them, so it went back.")
        return 1
    start_chosen(chosen)
    # Count them coming up, for the screen and Core.
    deadline = time.time() + 600
    while True:
        up = sum(systemctl("is-active", "--quiet", f"pocket-{a}.service").returncode == 0 for a in missing)
        progress("starting", missing, f"Starting them: {up} of {n} running", running=up)
        if up == n or time.time() > deadline:
            break
        time.sleep(5)
    say("Done: " + ", ".join(missing) + (" is" if n == 1 else " are") + " on the box")
    progress("done", missing, f"{some.capitalize()} installed", running=up)
    return 0


if __name__ == "__main__":
    os.makedirs(STATE, exist_ok=True)
    held = lock()
    sys.exit(apply() if "--apply" in sys.argv[1:] else main())
