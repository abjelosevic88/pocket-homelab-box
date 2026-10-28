# Pocket Box

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A NixOS appliance that runs [Pocket Core](https://github.com/abjelosevic88/pocket-homelab-core) and the Pocket apps on one machine. Boot the installer from a USB stick, pick a disk, reboot. Then open `http://pocket.local` from a phone or laptop on the same network: install the box's certificate there once, and continue to Pocket Core at `https://core.pocket.local`.

The whole system is declared in this flake. The installer ISO already contains the finished system, so installing needs no network.

## What's on the box

All 39 Pocket apps, each at `https://<slug>.pocket.local` (the port is where it listens on loopback):

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

| Service | Address | Used by |
|---|---|---|
| Jellyfin | `jellyfin.pocket.local` | Pocket Watch, Pocket Subtitles |
| Navidrome | `navidrome.pocket.local` | Pocket Music |
| Immich | `immich.pocket.local` | Pocket Photos |
| OnlyOffice Document Server | `onlyoffice.pocket.local` | Pocket Office |

Nobody has to open these services' setup screens:
- **First boot:** `pocket-box-backends` creates a box administrator (`pocket-box`) and an API key in Jellyfin, Navidrome and Immich. It also adds Jellyfin's Movies and Shows libraries. The credentials stay in `/var/lib/pocket-box/backends/`, readable by root only.
- **Handing them to Core:** it writes the services and their admin keys to `core-services.json`. Core reads that file at start (`SERVICES_FILE`, as a systemd credential) and turns on the connectors that make accounts.
- **Each person's own account:** the owner's first-run account in Core, and everyone added later, gets an account and key in each service. Watch, Music and Photos use those keys, so each person has their own resume points, playlists and photos.

Pocket Office and OnlyOffice share a JWT secret that is generated on the first boot.

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

## Addresses, HTTPS and sign-in

Caddy is the only thing listening on the network (ports 80 and 443). The apps and services listen on loopback.
- **Every app and service:** served at `https://<name>.pocket.local`, with certificates from Caddy's local CA, *Pocket Box Root CA*.
- **`http://pocket.local`:** stays plain http on purpose. It's a landing page where each phone or computer downloads that CA once, with steps for iPhone, Mac, Android and Windows. It then links to Core.
- **`https://pocket.local`:** redirects to Core.

`pocket.local` and all 43 names are announced over mDNS. `pocket-box-mdns-aliases` follows address changes and spreads the records over several Avahi groups, because Avahi allows 32 entries per group.
- **Apple devices and Linux with Avahi:** resolve these multi-label `.local` names.
- **Android and some Windows versions:** may not.

The box resolves its own names through `/etc/hosts`. The apps trust the CA through `SSL_CERT_FILE`, so they reach each other and Core by their public names.

Core's first-run screen creates the admin account. Every app has "Sign in with Pocket Core", and the first person to sign in becomes that app's admin. In the VM, the Core account signed in to all 38 apps this way and was admin in each.

Options: `pocket.box.domain` (default `<hostname>.local`), `pocket.box.httpsPort` and `pocket.box.httpPort`.

## Build

Needs Nix with flakes on x86_64 Linux.

```sh
nix build .#iso       # result/iso/pocket-box-installer.iso
nix run .#vm          # the box in a VM: http://pocket.localhost:8080, then https://core.pocket.localhost:8443
nix build .#habits    # a single app
```

Write the ISO to a USB stick (`dd`, Etcher), boot the target PC from it in UEFI mode and run `sudo pocket-install`. It asks for the disk, makes you type the disk name twice, erases it, creates an ESP (`POCKET-BOOT`) and an ext4 root (`pocket-root`), then installs. The installer has a shell on the screen and on the first serial port.

On a PC with a TPM 2.0, the installer encrypts the root partition with LUKS2. The TPM unlocks it at every boot, bound to the firmware's Secure Boot state (PCR 7), so updates never lock it. The installer shows a **recovery key** once; the box asks for it on its screen only if the TPM refuses, for example after a motherboard swap or a firmware reset. On a PC without a TPM, or with `pocket-install --no-encrypt`, the disk stays plain, because a headless box couldn't ask anyone for a password at boot. The ISO carries both variants (`nixosConfigurations.box` and `box-encrypted`).

The console account `pocket` has no password until the owner sets one in the setup wizard. SSH is off.

## First run

1. Open `http://pocket.local`, install the certificate, and continue to `https://core.pocket.local`.
2. Create the first account. It becomes the admin of Core and of every app.
3. Core opens the **setup wizard** (`/welcome`). It covers the time zone (the apps restart to pick it up), the network and Wi-Fi, Tailscale (a login link or an auth key) and the console password, and shows how the disk is protected. *Do this later* skips it, and everything stays under **Settings → System**.

Core runs unprivileged, so `pocket-box-agent` makes these changes as root (`modules/agent.py`, `modules/system.nix`). It's reachable only through `/run/pocket-box-agent/agent.sock`, which only Core's group can open. NetworkManager runs the network (Ethernet by DHCP, Wi-Fi joined from the wizard) and Tailscale is installed but logged out. The time zone is UTC until the wizard sets it.

## Testing the installer

```sh
scripts/install-test.sh
```

This builds the ISO and boots it in QEMU (KVM + OVMF). It runs `pocket-install` on a blank 32 GB virtual disk over the serial console, then boots that disk. It downloads the CA from the landing page and checks every app and service over https through Caddy, verifying certificates against that CA (host ports 28443/28080). Then it runs the owner's first visit:
- creates the account in Core and waits for that person's Jellyfin, Navidrome and Immich accounts
- requires Watch, Music and Photos to report their service connected after signing in with Pocket Core
- goes through the wizard via Core's API: time zone, console password, and a disk state that matches the install

By default the VM gets a software TPM (swtpm), so the disk is encrypted and the installer must show a recovery key. `TPM=0` tests a PC without a TPM (plain disk). `BOOT_ONLY=1` boots the installed disk again, which also checks the TPM unlock on a second boot. Logs go to `.installtest/`.

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
modules/box.nix       pocket.box.* options: app services, first-boot secrets, Avahi
modules/proxy.nix     Caddy, local CA, landing page, mDNS names
modules/system.nix    NetworkManager, Tailscale, console account, the box agent
modules/agent.py      the box agent (time zone, Wi-Fi, Tailscale, console password, disk status)
modules/services.nix  Jellyfin, Navidrome, Immich, OnlyOffice; first-boot accounts for Core
modules/backends-bootstrap.py  the first-boot setup of those services
hosts/box.nix         the installed system (hardware-agnostic, file systems by label)
hosts/encrypted.nix   the encrypted variant: LUKS2 root unlocked by the TPM
hosts/installer.nix   the ISO and pocket-install
scripts/              install-test
```

## Not done yet

- Updates: a binary cache and `system.autoUpgrade` with health-gated rollback. aarch64 images.
- CI that rebuilds the hashes and the ISO.
- The apps on the move: Tailscale gets the box onto your tailnet, but the `https://<app>.pocket.local` names and the local CA only work on the LAN.
- Installing the CA from the native client during pairing, instead of the landing page.
- "Sign in with Pocket Core" inside Immich and Jellyfin themselves. The Pocket apps already sign in for you; Jellyfin's needs the SSO plugin.
- Collabora as a second Office engine, and Bazarr plus the arr apps for Subtitles and Watch.
- Secure Boot (lanzaboote), which would make the TPM binding mean more.

## License

MIT
