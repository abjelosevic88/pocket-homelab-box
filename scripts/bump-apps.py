"""Move every Pocket app to its newest release tag (vX.Y.Z) and fix the build hashes.

  python3 scripts/bump-apps.py [--summary FILE]

For each app in apps.nix it asks GitHub for the repository's tags (GH_TOKEN or GITHUB_TOKEN raises
the rate limit). When the newest one is newer than the app's version, or the input is not pinned
to a tag yet, the flake input moves to github:owner/repo/vX.Y.Z and the version follows. Then
`nix flake update` locks the moved inputs and the moved apps are built; the hashes Nix reports as
wrong (npm and Go dependencies) are written into apps.nix and the build repeated until it passes.

Exits 0 with nothing changed, 0 with changes (listed in --summary as Markdown), 1 when an app does
not build for another reason than a hash.
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPS = os.path.join(ROOT, "apps.nix")
FLAKE = os.path.join(ROOT, "flake.nix")
FAKE = "lib.fakeHash"


def gh(path):
    req = urllib.request.Request("https://api.github.com/" + path, headers={"Accept": "application/vnd.github+json"})
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def semver(s):
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", s)
    return tuple(map(int, m.groups())) if m else None


def latest_tag(repo):
    tags = [t["name"] for t in gh(f"repos/{repo}/tags?per_page=100")]
    vers = sorted((semver(t), t) for t in tags if semver(t))
    return vers[-1][1] if vers else None


def block(text, slug):
    a = text.index(f"\n  {slug} = {{")
    return a, text.index("\n  };", a)


def set_field(text, slug, key, value):
    a, b = block(text, slug)
    part = re.sub(rf'(\n    {key} = )[^;]+;', lambda m: f'{m.group(1)}{value};', text[a:b], count=1)
    return text[:a] + part + text[b:]


def nix(*args, check=False):
    return subprocess.run(["nix", *args], cwd=ROOT, capture_output=True, text=True, check=check)


def main():
    summary_file = sys.argv[sys.argv.index("--summary") + 1] if "--summary" in sys.argv else None
    apps_txt, flake_txt = open(APPS).read(), open(FLAKE).read()
    catalog = re.findall(r'\n  ([a-z]+) = \{\n    title = "([^"]+)";\n    pname = "([^"]+)";\n    input = "([^"]+)";\n    version = "([^"]+)";', apps_txt)
    inputs = dict(re.findall(r'\n    (pocket-[a-z]+) = \{ url = "github:([^"]+)"; flake = false; \};', flake_txt))

    moved = []  # (slug, title, pname, input, old, new)
    for slug, title, pname, inp, version in catalog:
        ref = inputs[inp]
        repo = "/".join(ref.split("/")[:2])
        pinned = ref.split("/")[2] if ref.count("/") >= 2 else ""
        tag = latest_tag(repo)
        if not tag:
            print(f"{slug}: no release tag, left as is", file=sys.stderr)
            continue
        if semver(tag) <= semver(version) and pinned == tag:
            continue
        if semver(tag) < semver(version):
            print(f"{slug}: newest tag {tag} is older than {version}; pinning to it anyway", file=sys.stderr)
        new = tag.lstrip("v")
        flake_txt = flake_txt.replace(f'url = "github:{ref}";', f'url = "github:{repo}/{tag}";')
        apps_txt = set_field(apps_txt, slug, "version", f'"{new}"')
        moved.append((slug, title, pname, inp, version, new))

    if not moved:
        print("every app is on its newest release")
        return 0
    open(FLAKE, "w").write(flake_txt)
    open(APPS, "w").write(apps_txt)
    r = nix("flake", "update", *[m[3] for m in moved])
    if r.returncode != 0:
        print(r.stderr, file=sys.stderr)
        return 1

    # Build what moved; write back the hashes Nix says are wrong, until it builds.
    wanted = {f"{pname}-web-{new}-npm-deps": (slug, "npmDepsHash") for slug, _, pname, _, _, new in moved}
    wanted.update({f"{pname}-{new}-go-modules": (slug, "vendorHash") for slug, _, pname, _, _, new in moved})
    for attempt in range(4):
        r = nix("build", "--no-link", "--keep-going", *[f".#{m[0]}" for m in moved])
        if r.returncode == 0:
            break
        fixes = re.findall(r"fixed-output derivation '/nix/store/[a-z0-9]+-([^']+)\.drv':\s+specified:\s+\S+\s+got:\s+(\S+)", r.stderr)
        fixes = [(wanted[name], h) for name, h in fixes if name in wanted]
        if not fixes:
            print(r.stderr[-4000:], file=sys.stderr)
            return 1
        apps_txt = open(APPS).read()
        for (slug, key), h in fixes:
            apps_txt = set_field(apps_txt, slug, key, f'"{h}"')
        open(APPS, "w").write(apps_txt)
    else:
        print("hashes did not settle", file=sys.stderr)
        return 1

    lines = [f"- {title}: {old} → {new}" for _, title, _, _, old, new in moved]
    print("\n".join(lines))
    if summary_file:
        open(summary_file, "w").write("Apps moved to their newest release:\n\n" + "\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
