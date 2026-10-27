# Pocket Box

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A NixOS appliance that runs [Pocket Core](https://github.com/abjelosevic88/pocket-homelab-core) and the Pocket apps on one machine. Boot the installer from a USB stick, pick a disk, reboot. Then open `http://pocket.local:8179` from a phone or laptop on the same network.

The whole system is declared in this flake. The installer ISO already contains the finished system, so installing needs no network.

## What's on the box

| App | Port |
|---|---|
| Pocket Core (setup, sign-in, launcher, pairing) | 8179 |
| Pocket Habits | 8169 |
| Pocket Kitchen | 8176 |
| Pocket Notes | 8182 |

Every app runs as its own systemd service (`pocket-<slug>`) under a dynamic user, with its data in `/var/lib/pocket-<slug>`. On the first boot, `pocket-box-secrets` creates a registration key in `/var/lib/pocket-box/secrets.env`. Core and the apps share it, so each app registers with Core when it starts. No secret is built into the image.

The box announces itself as `pocket.local` over mDNS (Avahi). Core's first-run screen creates the admin account.

## Build

Needs Nix with flakes on x86_64 Linux.

```sh
nix build .#iso       # result/iso/pocket-box-installer.iso (~1.5 GB)
nix run .#vm          # the box in a VM, apps on localhost:8179, :8169 …
nix build .#habits    # a single app
```

Write the ISO to a USB stick (`dd`, Etcher), boot the target PC from it in UEFI mode and run `sudo pocket-install`. It asks for the disk, makes you type the disk name twice, erases it, creates an ESP (`POCKET-BOOT`) and an ext4 root (`pocket-root`), then installs. The installer has a shell on the screen and on the first serial port.

The installed system has a console-only user `pocket` with the password `pocket`. SSH is off.

## Testing the installer

```sh
scripts/install-test.sh
```

This builds the ISO and boots it in QEMU (KVM + OVMF). It runs `pocket-install` on a blank 8 GB virtual disk over the serial console, then boots that disk and checks every app's `/healthz` on host ports +10000 (18179, 18169 …). Logs go to `.installtest/`.

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

- The remaining Pocket apps, and their third-party dependencies (Jellyfin, Navidrome, Immich, OnlyOffice) using the NixOS modules that already exist.
- HTTPS and nicer addresses (`habits.pocket.local` or paths) behind one reverse proxy.
- A first-boot wizard that also sets the system password, Wi-Fi and Tailscale. Disk encryption with TPM unlock.
- Signing in once for all apps: today each app still has its own first-run admin, and "Sign in with Pocket Core" has not been tested on the box yet.
- Updates: a binary cache and `system.autoUpgrade` with health-gated rollback. aarch64 images.
- CI that rebuilds the hashes and the ISO.

## License

MIT
