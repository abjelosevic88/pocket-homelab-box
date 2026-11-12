<p align="center">
  <img src="docs/icon.svg" width="72" alt="">
</p>
<h1 align="center">Pocket Box</h1>
<p align="center">
  A NixOS appliance that turns a spare PC into a home server running <a href="https://github.com/abjelosevic88/pocket-homelab-core">Pocket Core</a> and all 82 Pocket apps: HTTPS on every app, one sign-in, Jellyfin, Navidrome, Immich and ONLYOFFICE set up on first boot, TPM disk encryption, and nightly updates that roll themselves back.<br>
  <b>Boot the USB stick · pick a disk · open pocket.local.</b>
</p>
<p align="center">
  <a href="https://github.com/abjelosevic88/pocket-homelab-box/actions"><img src="https://github.com/abjelosevic88/pocket-homelab-box/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <img src="https://img.shields.io/badge/NixOS-unstable-5277C3?logo=nixos&logoColor=white" alt="NixOS">
  <img src="https://img.shields.io/badge/platform-x86__64%20UEFI-blue" alt="x86_64 UEFI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT"></a>
  <a href="https://pockethomelab.com/box"><img src="https://img.shields.io/badge/website-pockethomelab.com%2Fbox-0e7490" alt="Website"></a>
</p>

---

Boot the installer from a USB stick, pick a disk, reboot. Open `http://pocket.local` from a phone or laptop on the same network and choose how the box gets its padlock: **Pocket's free address** (recommended; within a minute the box is at a name like `x7k2m9.box.pockethomelab.com`, with a Let's Encrypt certificate every browser already trusts), **your own domain on Cloudflare** (sign in with Cloudflare, and the box sets up `pocket.yourdomain` itself), or **the box's own certificate** (installed once on each device; no name on the internet). The page then takes you on to Pocket Core.

The whole system is declared in this flake. The installer ISO already contains the finished system, so installing needs no network.

## What's on the box

All 82 Pocket apps and Pocket Core, each at `https://<slug>.<the box's name>` (and `https://<slug>.pocket.local`; the port is where it listens on loopback). [pockethomelab.com/apps](https://pockethomelab.com/apps) has a page for every one of them.

| App | Port |
|---|---|
| Pocket Core (setup, sign-in, launcher, pairing) | 8179 |
| Pocket AI | 8195 |
| Pocket Alerts | 8217 |
| Pocket Audiobooks | 8202 |
| Pocket Backups | 8203 |
| Pocket Blog | 8246 |
| Pocket Blueprint | 8222 |
| Pocket Boards | 8223 |
| Pocket Bookshelf | 8171 |
| Pocket Calendar | 8190 |
| Pocket Chat | 8247 |
| Pocket Clips | 8173 |
| Pocket Contacts | 8191 |
| Pocket CRM | 8249 |
| Pocket Database | 8209 |
| Pocket Day | 8177 |
| Pocket Documents | 8183 |
| Pocket Draw | 8213 |
| Pocket Errors | 8256 |
| Pocket Family | 8257 |
| Pocket Files | 8187 |
| Pocket Fitness | 8240 |
| Pocket Flows | 8212 |
| Pocket Forms | 8248 |
| Pocket Games | 8226 |
| Pocket Garage | 8175 |
| Pocket Guitar | 8214 |
| Pocket Habits | 8169 |
| Pocket Health | 8199 |
| Pocket Home | 8229 |
| Pocket Horoscope | 8215 |
| Pocket Hub | 8185 |
| Pocket Inventory | 8170 |
| Pocket Invoicing | 8168 |
| Pocket Jobs | 8261 |
| Pocket Kitchen | 8176 |
| Pocket League | 8250 |
| Pocket Learn | 8218 |
| Pocket Library | 8204 |
| Pocket Lookout | 8224 |
| Pocket Mail | 8208 |
| Pocket Map | 8255 |
| Pocket Money | 8178 |
| Pocket Monitoring | 8192 |
| Pocket Movement | 8197 |
| Pocket Music | 8200 |
| Pocket Network | 8207 |
| Pocket Notes | 8182 |
| Pocket Nutrition | 8241 |
| Pocket Office | 8186 |
| Pocket Parcels | 8233 |
| Pocket Pets | 8232 |
| Pocket Photos | 8194 |
| Pocket Places | 8236 |
| Pocket Podcasts | 8181 |
| Pocket PR Review | 8220 |
| Pocket Projects | 8196 |
| Pocket Radio | 8216 |
| Pocket Reader | 8211 |
| Pocket Remote | 8259 |
| Pocket Renewals | 8230 |
| Pocket Rentals | 8253 |
| Pocket Requests | 8210 |
| Pocket Review | 8180 |
| Pocket Search | 8225 |
| Pocket Sign | 8234 |
| Pocket Sphere | 8227 |
| Pocket Split | 8172 |
| Pocket Still | 8206 |
| Pocket Subtitles | 8150 |
| Pocket Tables | 8252 |
| Pocket Tasks | 8184 |
| Pocket Time | 8219 |
| Pocket Trails | 8254 |
| Pocket Translate | 8251 |
| Pocket Travel | 8174 |
| Pocket Voice | 8237 |
| Pocket Wallet | 8238 |
| Pocket Wardrobe | 8258 |
| Pocket Watch | 8201 |
| Pocket Wealth | 8231 |
| Pocket Weather | 8239 |
| Pocket Wishlist | 8198 |

And the third-party services some of them sit on top of, from the NixOS modules in nixpkgs (each one can be switched off under `pocket.box.services`):

| Service | Address | Used by |
|---|---|---|
| Jellyfin | `jellyfin.pocket.local` | Pocket Watch, Pocket Subtitles |
| Navidrome | `navidrome.pocket.local` | Pocket Music |
| Immich | `immich.pocket.local` | Pocket Photos |
| OnlyOffice Document Server | `onlyoffice.pocket.local` | Pocket Office |
| SearXNG | loopback only (`127.0.0.1:8888`) | Pocket Search |
| Headless Chromium | loopback only (`127.0.0.1:9222`) | Pocket Lookout (pages that need JavaScript) |
| guacd (Apache Guacamole) | loopback only (`127.0.0.1:4822`) | Pocket Remote (VNC, RDP and SSH) |
| LibreTranslate | loopback only (`127.0.0.1:5000`), **off by default** | Pocket Translate (offline translation) |
| Radarr (films) | loopback only (`127.0.0.1:7878`) | Pocket Requests, Pocket Watch |
| Sonarr (shows) | loopback only (`127.0.0.1:8989`) | Pocket Requests, Pocket Watch |
| Prowlarr (NZB indexers) | loopback only (`127.0.0.1:9696`) | Radarr, Sonarr, Lidarr |
| SABnzbd (Usenet downloads) | loopback only (`127.0.0.1:8085`) | Radarr, Sonarr, Lidarr, Pocket Requests |
| Lidarr (albums) | loopback only (`127.0.0.1:8686`), with Requests **and** Music | Pocket Requests |
| Bazarr (subtitles) | loopback only (`127.0.0.1:6767`) | Pocket Subtitles |
| qBittorrent (torrents) | loopback only (`127.0.0.1:8090`), **off until switched on** in Core → Downloads | Radarr, Sonarr, Lidarr, Pocket Requests |

LibreTranslate brings PyTorch (about 3.5 GiB) and downloads its language models on the first start, so it's off unless you set `pocket.box.services.libretranslate.enable = true`. Without it Pocket Translate translates with Pocket AI.

Nobody has to open these services' setup screens:
- **First boot:** `pocket-box-backends` creates a box administrator (`pocket-box`) and an API key in Jellyfin, Navidrome and Immich. It also adds Jellyfin's Movies and Shows libraries. The credentials stay in `/var/lib/pocket-box/backends/`, readable by root only.
- **Handing them to Core:** it writes the services and their admin keys to `core-services.json`. Core reads that file at start (`SERVICES_FILE`, as a systemd credential) and turns on the connectors that make accounts.
- **Each person's own account:** the owner's first-run account in Core, and everyone added later, gets an account and key in each service. Watch, Music and Photos use those keys, so each person has their own resume points, playlists and photos.

Pocket Office and OnlyOffice share a JWT secret that is generated on the first boot, and so is SearXNG's secret key.

**Downloads** (Usenet first, torrents if the owner wants them). Radarr, Sonarr, Prowlarr, SABnzbd and qBittorrent come with Pocket Watch or Requests, Lidarr with Requests and Music together, Bazarr with Pocket Subtitles. All of them run on loopback with no site: Pocket Requests shows their queues, health and disk space, so the owner doesn't need their own pages. Core has no sign-in for third-party pages yet, and they aren't put on the network without one.
- **Keys:** `pocket-box-media-keys` makes every API key before the services first start (`/var/lib/pocket-box/media-keys/`, root only) and hands them over as environment (`RADARR__AUTH__APIKEY`…), SABnzbd's secret ini and Bazarr's settings. Their web UIs need a login (`pocket-box` and a password in the same file).
- **Wiring:** `pocket-box-backends` connects them on every boot, only where something is missing: root folders `/srv/media/{movies,tv,music}`, SABnzbd as the download client (categories `movies`, `tv`, `music`, `books`), Radarr, Sonarr and Lidarr as Prowlarr's applications (full sync, so indexers added once reach all three), SABnzbd in Prowlarr, Bazarr on Radarr and Sonarr with a default language profile. New films and shows get HD-1080p (the lower profiles are removed on a fresh install, as Pocket Requests takes the first), and files are renamed in the usual way.
- **Folders:** downloads land in `/srv/media/downloads/{incomplete,complete}`, on the same disk as the library, so importing is an instant move. The services join `pocket-media` and write group-writable files.
- **Handing them to Core:** they go into `core-services.json` too, for admins only and without a connector (there are no per-person accounts), with `owner_credential` so Core gives the box's key to the owner. Requests, Watch and Subtitles get them from Core as the box owner.
- **What the owner types in:** Core → Settings → System → **Downloads** (and a step in the setup wizard) talks to `pocket-box-downloads` (`modules/downloads.py`) on `/run/pocket-box-downloads/downloads.sock`, which only Core's group can open. It takes the Usenet provider (saved in SABnzbd and tested), NZB and torrent indexers (added to Prowlarr and tested; one that fails stays switched off), torrents on or off with their seeding limits, the VPN, and subtitle languages with an optional OpenSubtitles.com login (Bazarr). It has presets for well-known providers and indexers, and never sends a password or key back.
- **Torrents** stay off until the owner switches them on in Downloads, because peers see the home address: until then qBittorrent doesn't run and its download client in Radarr, Sonarr, Lidarr and Prowlarr is off. SABnzbd stays the first client (priority 1, qBittorrent 2) and Usenet indexers come before torrent ones. Torrents go to `/srv/media/downloads/torrents/{incomplete,complete/<category>}`, on the same disk, so the library gets hard links and seeding goes on after the import. Seeding stops at ratio 1.0 or after 7 days (changeable); qBittorrent then pauses the torrent and the arr app removes it. No UPnP. Presets: public sites that work in Prowlarr without FlareSolverr, and private trackers by their Prowlarr name with a login or key.
- **VPN for torrents:** a pasted WireGuard config (`wg-quick` format) is brought up by `pocket-box-vpn` for qBittorrent alone; the rest of the box keeps its own connection. Everything qBittorrent's user sends goes by a routing table of its own, which ends in *unreachable*, so when the tunnel is down qBittorrent has no way out (a kill switch), while the arr apps still reach its web UI on loopback. qBittorrent is also bound to the tunnel and uses the VPN's DNS. The box checks the tunnel shows another public address than the home one.
- **SABnzbd needs unrar,** which is unfree but redistributable, so the box allows that one package.

Every app runs as its own systemd service (`pocket-<slug>`) under a dynamic user, with its data in `/var/lib/pocket-<slug>`. The exceptions:
- **Backups and Database run as root.** They need to read the whole disk and every app's database.
- **Network gets `CAP_NET_RAW`** to ping and scan the LAN.

On the first boot, `pocket-box-secrets` creates a registration key in `/var/lib/pocket-box/secrets.env`. Core and the apps share it, so each app registers with Core when it starts. No secret is built into the image.

Media lives in `/srv/media` (`movies`, `tv`, `music`, `books`, `audiobooks`, `games`), owned by the `pocket-media` group. Navidrome reads `/srv/media/music`. Music, Audiobooks, Library, Games and Subtitles can write there. Pocket Sphere keeps its videos in its own `/var/lib/pocket-sphere/library` instead, so no other app sees them.

Tools the apps shell out to are put on their PATH:
- **Documents:** ocrmypdf, plus Tesseract with 16 languages
- **Translate:** poppler and the same Tesseract
- **Podcasts:** yt-dlp, deno and ffmpeg
- **Subtitles:** ffsubsync and alass
- **Backups:** restic and rclone
- **Pocket AI:** codex. Claude Code is unfree, so it is not in the image.

## Addresses, HTTPS and sign-in

Caddy is the only thing listening on the network (ports 80 and 443). The apps and services listen on loopback.

**How the box gets its padlock** is the owner's choice, made on `http://pocket.local` before anyone has an account, and changeable in Core → Settings → System → Secure address. `pocket-box-address` (`modules/address.py`) records it; `pocket-box-name` does the work. Until there is a choice the box asks nobody for anything (it doesn't send its home address to Pocket Names unless that is what the owner picked). Boxes that got a Pocket name before the choice existed keep it.

| | What happens |
|---|---|
| **Pocket's free address** (recommended) | below |
| **Your own domain on Cloudflare** | *Sign in with Cloudflare* (OAuth with PKCE; the client id comes from Pocket Names, which only passes the browser back to the box) or a pasted API token (a prefilled *Create token* link: Zone · Read, DNS · Edit). The box adds `<name>.<zone>` and `*.<name>.<zone>` as A records to the owner's zone (tagged with the comment "Pocket Box"; it refuses names already in use), keeps them on its home address, and gets the certificate over DNS-01 with lego's Cloudflare provider. Pocket Names isn't involved. A lapsed sign-in shows in Core |
| **The box's own certificate** | no public name; the local names and CA below |

Switching moves the box over once the new address works, then lets the old one go: the Pocket name is given back, the old Cloudflare records are removed. The landing page may only make the first choice, and only from that page (it must send `X-Pocket-Box`, which other sites can't add without asking); Core, as an admin, may change it any time.

**Pocket's free address.** Each box gets a name of its own from Pocket Names (`names.pockethomelab.com`), like `x7k2m9.box.pockethomelab.com`, and a Let's Encrypt certificate for it and every app under it. `pocket-box-name` (`modules/names.{nix,py}`) does this on a timer:
- **Asks as soon as it's chosen,** then every 3 minutes until the box has its name. In a VM against the live service the name and certificate were there 46 seconds after boot.
- **Points the name at the box's home address** (its address on the home network), again when it changes and twice a day as a sign of life.
- **Gets the certificate over DNS-01:** Pocket Names only answers Let's Encrypt's DNS check; the private key never leaves the box. It renews 30 days before the end.
- **Switches over once it works:** Caddy serves every app on the new name too, the box resolves it itself, and the apps restart with it in their public URLs (`pocket-box-env` swaps the local domain in their environment).

Until that has worked once (no internet, say), nothing changes: the box stays on its local names and its own CA, below. `pocket.box.names.enable = false` keeps it that way for good.

**Local names, the fallback.**
- **Every app and service:** also served at `https://<name>.pocket.local`, with certificates from Caddy's local CA, *Pocket Box Root CA*.
- **`http://pocket.local`:** stays plain http on purpose. It's the landing page: first it asks how the box should get its padlock (above); while the box gets its name it shows "Getting your box's secure address…" and moves on by itself once the name works. If this network can't reach the name (some routers block names that point into the home network) or there is no internet, it shows how to install the box's CA once, with steps for iPhone, Mac, Android and Windows, and links to Core.
- **`https://pocket.local`:** redirects to Core.

`pocket.local` and all 87 names are announced over mDNS. `pocket-box-mdns-aliases` follows address changes and spreads the records over several Avahi groups, because Avahi allows 32 entries per group.
- **Apple devices and Linux with Avahi:** resolve these multi-label `.local` names.
- **Android and some Windows versions:** may not.

The box resolves its own names through `/etc/hosts`. The apps trust the CA through `SSL_CERT_FILE`, so they reach each other and Core by their public names.

Core's first-run screen creates the admin account. Every app has "Sign in with Pocket Core", and the first person to sign in becomes that app's admin. In the VM, the Core account signed in to every app this way and was admin in each (checked with the first 38 apps).

Options: `pocket.box.domain` (default `<hostname>.local`), `pocket.box.httpsPort`, `pocket.box.httpPort`, and `pocket.box.names.{enable,server,acmeServer}`.

**The box's screen** shows the address to open (the public name once the box has it, else `pocket.local`), a QR code for it, and how the console login works: user `pocket`, and whether a console password is set, never the password (`modules/screen.py`).

## Download

Each [release](https://github.com/abjelosevic88/pocket-homelab-box/releases) has the installer ISO. It's bigger than GitHub's 2 GB limit per file, so it comes in parts; join them and check the result (the release notes have the exact commands, Windows too):

```sh
cat pocket-box-installer-<release>.iso.part[0-9]* > pocket-box-installer-<release>.iso
sha256sum -c pocket-box-installer-<release>.iso.sha256
```

Then write it to a USB stick (8 GB or more) with `dd`, Etcher or Rufus (DD mode) and follow [Install](#build) below. A box installed from any release updates itself from `stable` afterwards.

**Pocket Box Lite** (`pocket-box-lite-installer-<release>.iso`, one file) carries only Pocket Core with the base apps from `bundles.json` (Pocket AI, Alerts and Backups). See [Bundles and Lite](#bundles-and-pocket-box-lite).

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

1. Open `http://pocket.local` (or scan the QR code on the box's screen) and choose how the box gets its padlock. With Pocket's address or your own Cloudflare domain it moves on to Pocket Core on that name; with the box's own certificate it shows how to install it first.
2. Create the first account. It becomes the admin of Core and of every app.
3. Core opens the **setup wizard** (`/welcome`). It covers the secure address, the time zone (the apps restart to pick it up), the network and Wi-Fi, Tailscale (a login link or an auth key) and the console password, and shows how the disk is protected. *Do this later* skips it, and everything stays under **Settings → System**.

Core runs unprivileged, so `pocket-box-agent` makes these changes as root (`modules/agent.py`, `modules/system.nix`). It's reachable only through `/run/pocket-box-agent/agent.sock`, which only Core's group can open. NetworkManager runs the network (Ethernet by DHCP, Wi-Fi joined from the wizard) and Tailscale is installed but logged out. The time zone is UTC until the wizard sets it.

## Installing and removing apps

Every app ships in the box's system, each as its own service, and runs only while its marker `/var/lib/pocket-box/apps/<slug>` exists. **Core → Apps → Install an app** and **Remove** talk to `pocket-box-installer` (`modules/installer.py`), which speaks Core's installer protocol on a socket only Core's group can open, with a per-box token:
- **Install** makes the marker and starts the app, which registers with Core on its own.
- **Remove** stops it and drops the marker. Its data stays in `/var/lib/pocket-<slug>`, so installing it again brings everything back.
- **New apps:** on the first boot every app the box carries is installed (or only the chosen ones, see [Bundles and Lite](#bundles-and-pocket-box-lite)). Apps that arrive with a later update start out not installed, ready in Core.
- **An app the box doesn't carry** (Lite, or a box set up with bundles) is downloaded first; see below.

Apps update with the box, not one by one. Descriptions and icons come from the public app catalog when the box is online.

## Bundles and Pocket Box Lite

`bundles.json` lists app bundles (essentials, office, developer, media, family, money, health) and `base`, the apps Pocket Box Lite carries. `pocket-install` reads it, and so does [pockethomelab.com/box/bundles](https://pockethomelab.com/box/bundles), where you pick bundles and apps and get the line to type. The flake check `bundles` fails if a bundle names an app `apps.nix` doesn't have.

- `sudo pocket-install` without a choice (or with `--pick`, or `--apps` alone) shows a **checklist**: bundles first (ticking one ticks its apps), then every app. ↑/↓ move, Space ticks, `+` all, `-` none, a letter jumps to an app, Enter installs, Esc goes back to typing names. On Lite the base apps stay ticked; on the full ISO everything starts ticked.
- `sudo pocket-install office media voice` (any word that isn't a disk is a bundle or app; `--bundle office,media --apps voice` works too, and so do typed names) does the same without the checklist. The chosen apps, plus `base`, go to `/var/lib/pocket-box/apps.json`. `--help` lists the bundles. With every app chosen, the box keeps no list.
- A box with that list starts with just those apps. The full ISO has the rest on the disk, unused; the Lite ISO (`nix build .#iso-lite`) doesn't carry them, and **`pocket-box-apply`** downloads them on the first boot (it needs the internet then).
- `pocket-box-apply` (`modules/updater.py --apply`) builds this same release (its full revision is in `/etc/pocket-box/release.json`) with the box's list through `lib.boxToplevel { variant; apps; }`, gets the apps from the cache, switches, and checks the box is healthy. If not, it goes back and drops the new apps from the list. Core's **Install** of an app the box doesn't carry adds it to the list and runs it, showing its progress in Core.
- While apps are on their way, `update/apply.json` says how far (downloading, switching, starting: n of N running): the box's screen shows it, and so does Core's Apps page (through the installer's status). Core waits up to three hours for such an install.
- If this release's app builds are gone from the cache (a box that hasn't updated in a long time), `pocket-box-apply` takes the newest release instead, which also updates the box, rather than compiling apps on the box.
- On Lite, choosing "all" lists every app explicitly, so the box downloads them all; without a list a box counts as "every app the release has", which only the full ISO carries. CI also installs the Lite ISO with its base apps (`LITE=1 TPM=0 scripts/install-test.sh`).
- The nightly update builds the box's list too, so a box never grows apps it didn't choose. Remove takes an app off the list, and the next update leaves it out.
- Jellyfin, Navidrome, Immich, ONLYOFFICE and the download services run only with the apps that use them, so a small box stays small (Lite's system is about 3.3 GiB against 11.4 GiB for every app).

## Updates

Boxes follow the `stable` branch of this repository. Only CI moves `stable`, after the install test passed.
- **Nightly run:** at 04:00 (plus up to an hour) `pocket-box-update` builds the newest release of the box's own variant (`box` or `box-encrypted`). It downloads it from the binary cache when one is set, and builds it itself otherwise.
- **Health check:** it switches to the new release, then waits up to 10 minutes for every Pocket app to answer `/healthz` and for no Pocket service to fail.
- **Rollback:** if something doesn't come up, it switches back to the previous system and remembers that release as bad (`/var/lib/pocket-box/update/bad`), so it isn't tried again.
- **New kernel:** it takes over at the next restart; the nightly run restarts the box itself.

Settings → System → Updates in Core shows:
- the running release (`/etc/pocket-box/release.json`: the commit's date and time, and its revision)
- what the last run did
- *Check now*, an on/off switch, and *Restart now* when a new kernel is waiting

The binary cache is `pocket.box.updates.cache` (`url` and `publicKey`). Writing a release flake reference into `/var/lib/pocket-box/update/flake` makes a box follow another release, for support or tests.

## CI and releases

Apps are pinned to their **release tags** (`github:abjelosevic88/<repo>/vX.Y.Z`), and the tag is the version their pill shows. Tagging an app's repository is how it reaches the boxes.

`.github/workflows/ci.yml`:
- **Pushes to `main` and pull requests:** build both systems and run the install test (encrypted with a software TPM, then a second boot). When `main` passes, it's pushed to `stable`.
- **Nightly:** `scripts/bump-apps.py` first moves every app to its newest release tag and fixes the npm and Go hashes. If anything moved, it builds and tests that, commits it to `main` and releases it to `stable`.
- **Cache:** everything built goes to the Cachix cache named in the repository variable `CACHIX_CACHE`, using the secret `CACHIX_AUTH_TOKEN`.
- **Releases:** pushing a tag `vYYYY.MM.DD` runs `.github/workflows/release.yml`. It builds the installer ISO from that commit (from the cache, so after CI passed it's mostly downloads), splits it into parts under 2 GB and publishes a GitHub release with the parts, their checksums and the app versions.

`scripts/bump-apps.py` also runs locally (`GH_TOKEN` raises GitHub's rate limit).

## Testing the installer

```sh
scripts/install-test.sh
```

This builds the ISO and boots it in QEMU (KVM + OVMF). VMs never ask Pocket Names for a name (`-fw_cfg name=opt/pocket/names,string=off`; `string=pocket` instead picks Pocket's address without asking), so the test covers the local names and CA. It runs `pocket-install` on a blank 32 GB virtual disk over the serial console, then boots that disk. It downloads the CA from the landing page and checks every app and service over https through Caddy, verifying certificates against that CA (host ports 28443/28080). Then it runs the owner's first visit:
- creates the account in Core and waits for that person's Jellyfin, Navidrome and Immich accounts
- requires Watch, Music and Photos to report their service connected after signing in with Pocket Core
- goes through the wizard via Core's API: time zone, console password, and a disk state that matches the install

`scripts/update-test.sh`, after the install test, boots the installed disk and serves it two releases. In the first, a harmless change must install. In the second, Pocket Habits fails to start, so the box must go back by itself, and then skip that release on the next run.

By default the VM gets a software TPM (swtpm), so the disk is encrypted and the installer must show a recovery key. `TPM=0` tests a PC without a TPM (plain disk). `BOOT_ONLY=1` boots the installed disk again, which also checks the TPM unlock on a second boot. Logs go to `.installtest/`.

## Adding or updating an app

Apps are listed in [`apps.nix`](apps.nix), and each one's source is a flake input pinned in `flake.lock`. All of them build the same way ([`lib/mkPocketApp.nix`](lib/mkPocketApp.nix)): the React UI with `buildNpmPackage`, then the Go binary with the UI embedded.

- **Update:** tag a release in the app's repository (`vX.Y.Z`). The nightly CI run, or `python3 scripts/bump-apps.py` locally, moves the input to the tag, sets `version` and fixes the hashes.
- **Add:**
  1. Add the input to `flake.nix` as `github:abjelosevic88/<repo>/vX.Y.Z` (`flake = false`), and an entry to `apps.nix` with both hashes set to `lib.fakeHash`.
  2. `nix build .#<slug>`, then paste the `got:` hash from the error. Do this once for `npmDepsHash` and once for `vendorHash`.

## Layout

```
flake.nix             inputs, overlay (pkgs.pocket.<slug>), box / installer systems, iso / vm packages
apps.nix              the app catalog: pname, version, port, hashes
lib/mkPocketApp.nix   UI + Go build for one app
modules/box.nix       pocket.box.* options: app services, first-boot secrets, Avahi
modules/proxy.nix     Caddy, local CA, landing page, mDNS names
modules/names.nix     the public name and its Let's Encrypt certificate; modules/names.py does the work
modules/address.py    the owner's choice: Pocket's address, own domain on Cloudflare, or own certificate
modules/installer.py  Install and Remove for Core's app store
modules/screen.py     the address, QR code and console login shown on the box's screen
modules/system.nix    NetworkManager, Tailscale, console account, the box agent
modules/agent.py      the box agent (time zone, Wi-Fi, Tailscale, console password, disk status, updates)
modules/updates.nix   nightly updates; modules/updater.py does the switch, health check and rollback
modules/services.nix  Jellyfin, Navidrome, Immich, OnlyOffice, SearXNG, Chromium, the download services; first-boot accounts for Core
modules/backends-bootstrap.py  the first-boot setup of those services, and the download services' wiring
modules/downloads.py  Usenet provider, indexers and subtitle languages for Core's Downloads settings
hosts/box.nix         the installed system (hardware-agnostic, file systems by label)
hosts/encrypted.nix   the encrypted variant: LUKS2 root unlocked by the TPM
hosts/installer.nix   the ISO and pocket-install
scripts/              install-test, update-test, bump-apps, release-notes
tests/                NixOS VM tests: Pocket AI's jail, SearXNG and Chromium (nix build .#checks.x86_64-linux.engines)
.github/workflows/    ci.yml: build, test, release to stable, nightly app bumps; release.yml: the ISO on GitHub
```

## Not done yet

- Boxes evaluate the release flake themselves, which downloads every app's source from GitHub. CI could publish each variant's store path, so a box only fetches the finished system from the cache.
- Boot counting: a release that doesn't boot at all still needs someone to pick the previous one in the boot menu. aarch64 images.
- The apps on the move: the public name points at the box's home address, so it works at home. Tailscale gets the box onto your tailnet, but the names don't follow you there yet.
- "Sign in with Pocket Core" inside Immich and Jellyfin themselves. The Pocket apps already sign in for you; Jellyfin's needs the SSO plugin.
- Collabora as a second Office engine.
- Bazarr's post-processing hook into Pocket Subtitles: the hook needs a Pocket Subtitles token, which the box can't make yet, so the owner pastes the command from Subtitles → Settings → Integrations into Bazarr once.
- Sites for Radarr, Sonarr, SABnzbd and the rest behind Core's admin sign-in.
- Secure Boot (lanzaboote), which would make the TPM binding mean more.

## License

MIT
