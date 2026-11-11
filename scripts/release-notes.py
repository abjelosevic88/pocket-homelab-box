"""Markdown notes for a GitHub release of the installer ISO: how to join and write it, and what's on it.

  python3 scripts/release-notes.py TAG ISO_NAME [PART ...] > notes.md
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    tag, iso, parts = sys.argv[1], sys.argv[2], sys.argv[3:]
    apps_txt = open(os.path.join(ROOT, "apps.nix")).read()
    catalog = re.findall(r'\n  "?[a-z][a-z0-9-]*"? = \{\n    title = "([^"]+)";\n    pname = "[^"]+";\n    input = "([^"]+)";\n    version = "([^"]+)";', apps_txt)
    flake_txt = open(os.path.join(ROOT, "flake.nix")).read()
    repos = {i: "/".join(r.split("/")[:2]) for i, r in re.findall(r'\n    (pocket-[a-z0-9-]+) = \{ url = "github:([^"]+)"; flake = false; \};', flake_txt)}
    core = [c for c in catalog if c[1] == "pocket-core"]
    others = sorted((c for c in catalog if c[1] != "pocket-core"), key=lambda c: c[0])

    out = [
        f"The Pocket Box installer: Pocket Core and all {len(others)} Pocket apps, Jellyfin, Navidrome, Immich, ONLYOFFICE, SearXNG and guacd, "
        "on NixOS for x86_64 PCs that boot in UEFI mode. Installing needs no network.",
        "",
        "## Download",
        "",
        f"The ISO is bigger than GitHub's 2 GB limit per file, so it comes in {len(parts)} parts. Download all of them and `{iso}.sha256`, then join and check:",
        "",
        "```sh",
        f"cat {' '.join(parts)} > {iso}",
        f"sha256sum -c {iso}.sha256",
        "```",
        "",
        f"Windows (`cmd`): `copy /b {' + '.join(parts)} {iso}`, then compare `certutil -hashfile {iso} SHA256` with the `.sha256` file.",
        "",
        "## Install",
        "",
        "1. Write the ISO to a USB stick (8 GB or more) with `dd`, balenaEtcher or Rufus (DD mode).",
        "2. Boot the PC from it in UEFI mode and run `sudo pocket-install`. It erases the disk you pick. With a TPM 2.0 the disk is encrypted and unlocked by the TPM; write down the recovery key it shows.",
        "3. Reboot, then open `http://pocket.local` from a phone or laptop on the same network: install the box's certificate there once and continue to `https://core.pocket.local`. The first account becomes the admin.",
        "",
        "The box updates itself every night from the `stable` branch and rolls back a release that doesn't come up.",
        "",
        "## What's on it",
        "",
        "| App | Version |",
        "|---|---|",
    ]
    for title, inp, version in core + others:
        repo = repos.get(inp)
        name = f"[{title}](https://github.com/{repo}/releases/tag/v{version})" if repo else title
        out.append(f"| {name} | {version} |")
    lite = os.environ.get("LITE_ISO", "")
    if lite:
        bundles = __import__("json").load(open(os.path.join(ROOT, "bundles.json")))
        out += [
            "",
            "## Pocket Box Lite",
            "",
            f"`{lite}` is one file and much smaller: Pocket Core with {', '.join(bundles['base'])}. In `sudo pocket-install` pick bundles or apps "
            "(for example `sudo pocket-install --bundle office,media`, or answer its question); the box downloads them on its first boot, so it "
            "needs the internet then. More apps any time in Pocket Core → Apps → Install an app. Check it with "
            f"`sha256sum -c {lite}.sha256`.",
            "",
            "Bundles: " + "; ".join(f"**{b['id']}** ({len(b['apps'])} apps)" for b in bundles["bundles"]) + ". Pick them on [pockethomelab.com/box/bundles](https://pockethomelab.com/box/bundles).",
        ]
    print("\n".join(out))


if __name__ == "__main__":
    main()
