# Pocket Box

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A NixOS appliance that runs [Pocket Core](https://github.com/abjelosevic88/pocket-homelab-core) and the Pocket apps on one machine. Boot the installer from a USB stick, pick a disk, reboot. Then open `http://pocket.local:8179` from a phone or laptop on the same network.

The whole system is declared in this flake. The installer ISO already contains the finished system, so installing needs no network.

## What's on the box

All 39 Pocket apps, each on its own port:

| App | Port |
|---|---|
| Pocket Core (setup, sign-in, launcher, pairing) | 8179 |
| Pocket AI | 8195 |
| Pocket Audiobooks | 8202 |
| Pocket Backups | 8203 |
| Pocket Bookshelf | 8171 |
| Pocket Calendar | 8190 |
| Pocket Clips | 8173 |
| Pocket Contacts | 8191 |
| Pocket Database | 8209 |
| Pocket Day | 8177 |
| Pocket Documents | 8183 |
| Pocket Files | 8187 |
| Pocket Garage | 8175 |
| Pocket Habits | 8169 |
| Pocket Health | 8199 |
| Pocket Hub | 8185 |
| Pocket Inventory | 8170 |
| Pocket Invoicing | 8168 |
| Pocket Kitchen | 8176 |
| Pocket Library | 8204 |
| Pocket Mail | 8208 |
| Pocket Money | 8178 |
| Pocket Monitoring | 8192 |
| Pocket Movement | 8197 |
| Pocket Music | 8200 |
| Pocket Network | 8207 |
| Pocket Notes | 8182 |
| Pocket Office | 8186 |
| Pocket Photos | 8194 |
| Pocket Podcasts | 8181 |
| Pocket Projects | 8196 |
| Pocket Review | 8180 |
| Pocket Split | 8172 |
| Pocket Still | 8206 |
| Pocket Subtitles | 8150 |
| Pocket Tasks | 8184 |
| Pocket Travel | 8174 |
| Pocket Watch | 8201 |
| Pocket Wishlist | 8198 |

And the third-party services some of them sit on top of, from the NixOS modules in nixpkgs (each one can be switched off under `pocket.box.services`):

| Service | Port | Used by |
|---|---|---|
| Jellyfin | 8096 | Pocket Watch, Pocket Subtitles |
| Navidrome | 4533 | Pocket Music |
| Immich | 2283 | Pocket Photos |
| OnlyOffice Document Server | 8166 | Pocket Office |

The apps get these services' URLs automatically. Accounts and API keys are created in each service's own first-run screen. Pocket Office and OnlyOffice share a JWT secret that is generated on the first boot.

Every app runs as its own systemd service (`pocket-<slug>`) under a dynamic user, with its data in `/var/lib/pocket-<slug>`. The exceptions:
- **Backups and Database run as root.** They need to read the whole disk and every app's database.
- **Network gets `CAP_NET_RAW`** to ping and scan the LAN.

On the first boot, `pocket-box-secrets` creates a registration key in `/var/lib/pocket-box/secrets.env`. Core and the apps share it, so each app registers with Core when it starts. No secret is built into the image.

Media lives in `/srv/media` (`movies`, `tv`, `music`, `books`, `audiobooks`), owned by the `pocket-media` group. Navidrome reads `/srv/media/music`. Music, Audiobooks, Library and Subtitles can write there.

Tools the apps shell out to are put on their PATH:
- **Documents:** ocrmypdf, plus Tesseract with 16 languages
- **Podcasts:** yt-dlp, deno and ffmpeg
- **Subtitles:** ffsubsync and alass
- **Backups:** restic and rclone
- **Pocket AI:** codex. Claude Code is unfree, so it is not in the image.

The box announces itself as `pocket.local` over mDNS (Avahi). Core's first-run screen creates the admin account.

## Build

Needs Nix with flakes on x86_64 Linux.

```sh
nix build .#iso       # result/iso/pocket-box-installer.iso
nix run .#vm          # the box in a VM, apps on localhost:8179, :8169 …
nix build .#habits    # a single app
```

Write the ISO to a USB stick (`dd`, Etcher), boot the target PC from it in UEFI mode and run `sudo pocket-install`. It asks for the disk, makes you type the disk name twice, erases it, creates an ESP (`POCKET-BOOT`) and an ext4 root (`pocket-root`), then installs. The installer has a shell on the screen and on the first serial port.

The installed system has a console-only user `pocket` with the password `pocket`. SSH is off.

## Testing the installer

```sh
scripts/install-test.sh
```

This builds the ISO and boots it in QEMU (KVM + OVMF). It runs `pocket-install` on a blank 32 GB virtual disk over the serial console, then boots that disk and checks every app's `/healthz` on host ports +20000 (28179, 28169 …). Logs go to `.installtest/`.

## Adding or updating an app

Apps are listed in [`apps.nix`](apps.nix), and each one's source is a flake input pinned in `flake.lock`. All of them build the same way ([`lib/mkPocketApp.nix`](lib/mkPocketApp.nix)): the React UI with `buildNpmPackage`, then the Go binary with the UI embedded.

1. Add the input to `flake.nix` (`flake = false`) and an entry to `apps.nix` with both hashes set to `lib.fakeHash`.
2. `nix build .#<slug>`, then paste the `got:` hash from the error. Do this once for `npmDepsHash` and once for `vendorHash`.
3. To update: `nix flake update <input>`, bump `version`, and redo step 2 for any hash that changed.

## Layout

```
flake.nix             inputs, overlay (pkgs.pocket.<slug>), box / installer systems, iso / vm packages
apps.nix              the app catalog: pname, version, port, hashes
lib/mkPocketApp.nix   UI + Go build for one app
modules/box.nix       pocket.box.* options: services, first-boot secrets, Avahi, firewall
hosts/box.nix         the installed system (hardware-agnostic, file systems by label)
hosts/installer.nix   the ISO and pocket-install
scripts/              install-test
```

## Not done yet

- Setting up the third-party services from Core: making the Jellyfin/Navidrome/Immich accounts and handing their keys to the apps (Core's connectors already do this for Immich and Jellyfin on the home server).
- Collabora as a second Office engine, and Bazarr plus the arr apps for Subtitles and Watch.
- HTTPS and nicer addresses (`habits.pocket.local` or paths) behind one reverse proxy.
- A first-boot wizard that also sets the system password, Wi-Fi and Tailscale. Disk encryption with TPM unlock.
- Signing in once for all apps: today each app still has its own first-run admin, and "Sign in with Pocket Core" has not been tested on the box yet.
- Updates: a binary cache and `system.autoUpgrade` with health-gated rollback. aarch64 images.
- CI that rebuilds the hashes and the ISO.

## License

MIT
