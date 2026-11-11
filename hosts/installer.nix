# The installer ISO. It carries the finished box system in its store, so installing needs no network:
# boot it, run `sudo pocket-install`, pick the disk, reboot.
#
# On a PC with a TPM 2.0 the root partition is encrypted (LUKS2), unlocked at boot by the TPM; the
# installer shows a recovery key once, with a QR code. Without a TPM, or with --no-encrypt, the disk
# is plain: a headless box could not ask anyone for a password at boot.
#
# Apps: `--bundle office,media` / `--apps notes,tasks` (or the question pocket-install asks) choose them;
# the list goes onto the disk as /var/lib/pocket-box/apps.json and the box starts with just those. The
# full ISO carries every app; Pocket Box Lite (lite = true) carries Pocket Core and the base apps only and
# downloads the rest on the first boot (it needs the internet then).
{ config, lib, pkgs, modulesPath, boxSystem, boxSystemEncrypted, bundles, catalog, lite, ... }:

let
  appTitles = lib.mapAttrs (_: app: app.title) (lib.filterAttrs (slug: _: slug != "core") catalog);
  pickConfig = pkgs.writeText "pocket-pick-apps.json" (builtins.toJSON { inherit bundles; apps = appTitles; });
  pick-apps = pkgs.writers.writePython3 "pocket-pick-apps" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./pick-apps.py);
  baseNames = lib.concatMapStringsSep ", " (slug: appTitles.${slug}) bundles.base;
  pocket-install = pkgs.writeShellApplication {
    name = "pocket-install";
    runtimeInputs = with pkgs; [ util-linux parted dosfstools e2fsprogs coreutils gnugrep gnused cryptsetup systemd qrencode jq config.system.build.nixos-install ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "Run it as root: sudo pocket-install" >&2
        exit 1
      fi
      encrypt=yes
      pick=""
      choose=no
      disk=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --no-encrypt) encrypt=no ;;
          --pick) choose=yes ;;
          --apps|--bundle|--bundles)
            # A name after it is the choice; nothing (or the disk) opens the checklist.
            if [ $# -ge 2 ] && [ "''${2#-}" = "$2" ] && [ ! -b "/dev/''${2#/dev/}" ]; then
              pick="$pick $2"; shift
            else
              choose=yes
            fi ;;
          --apps=*|--bundle=*|--bundles=*) pick="$pick ''${1#*=}" ;;
          -h|--help)
            echo "sudo pocket-install [disk] [--bundle office,media] [--apps notes,tasks] [--pick] [--no-encrypt]"
            echo "Without a choice (or with --pick, or --apps alone) it shows a checklist of every app."
            echo "Bundles:"; ${pick-apps} ${pickConfig} --menu
            exit 0 ;;
          *) disk="$1" ;;
        esac
        shift
      done

      # Which apps. Not given on the command line: a checklist (Space ticks, Enter installs); Esc there,
      # or a terminal curses can't drive, falls back to typing bundle and app names.
      if { [ -z "''${pick// /}" ] || [ "$choose" = yes ]; } && [ -t 0 ]; then
        if ${pick-apps} ${pickConfig} --choose /tmp/pocket-apps ${lib.optionalString lite "--lite"}; then
          pick=$(cat /tmp/pocket-apps)
          [ -n "''${pick// /}" ] || pick=base
        else
          pick=""
        fi
      fi
      if [ -z "''${pick// /}" ] && [ -t 0 ]; then
        echo "Which apps should this box have? Bundles:"
        ${pick-apps} ${pickConfig} --menu
        echo "Type bundles and apps, e.g.  office, media  or  notes, tasks  (all of them: pockethomelab.com/box/bundles)."
        ${if lite
          then ''read -rp "Or press Enter for just Pocket Core with ${baseNames}: " pick''
          else ''read -rp "Or press Enter for every app (${toString (lib.length (lib.attrNames appTitles))}): " pick''}
        [ -z "''${pick// /}" ] && pick=${if lite then "base" else "all"}
      fi
      [ -z "''${pick// /}" ] && pick=${if lite then "base" else "all"}
      apps=""
      if [ "$pick" != base ]; then
        if ! apps=$(${pick-apps} ${pickConfig} "$pick"); then exit 1; fi
      else
        apps=$(${pick-apps} ${pickConfig} "")
      fi
      echo
      if [ -n "$apps" ]; then
        echo "Apps: Pocket Core and $(echo "$apps" | wc -l) more: $(echo "$apps" | paste -sd, - | sed 's/,/, /g')"
        ${lib.optionalString lite ''
        extra=$(echo "$apps" | grep -cvxF -e ${lib.concatStringsSep " -e " bundles.base} || true)
        if [ "$extra" -gt 0 ]; then echo "The box downloads $extra of them on its first boot, so it needs the internet then."; fi
        ''}
      else
        echo "Apps: every Pocket app."
      fi
      echo

      echo "Disks:"
      lsblk -d -e 7,11 -o NAME,SIZE,MODEL,TRAN
      echo
      if [ -z "$disk" ]; then
        read -rp "Install Pocket Box on which disk (e.g. nvme0n1, sda)? " disk
      fi
      disk="/dev/''${disk#/dev/}"
      if [ ! -b "$disk" ]; then
        echo "$disk is not a disk." >&2
        exit 1
      fi

      tpm=no
      if [ "$encrypt" = yes ] && [ -e /dev/tpmrm0 ] && systemd-cryptenroll --tpm2-device=list 2>/dev/null | grep -q /dev/; then
        tpm=yes
      fi
      echo
      if [ "$tpm" = yes ]; then
        echo "This PC has a TPM: the disk will be encrypted and unlock itself at boot."
      elif [ "$encrypt" = yes ]; then
        echo "This PC has no TPM 2.0: the disk will NOT be encrypted (nobody could type a password at boot)."
      fi
      echo "EVERYTHING on $disk will be erased."
      read -rp "Type the disk name again to continue: " again
      if [ "/dev/''${again#/dev/}" != "$disk" ]; then
        echo "Names differ, nothing was changed." >&2
        exit 1
      fi

      umount -R /mnt 2>/dev/null || true
      cryptsetup close pocket-root 2>/dev/null || true
      wipefs -af "$disk"
      rootname=root
      if [ "$tpm" = yes ]; then rootname=pocket-crypt; fi
      parted -s "$disk" -- mklabel gpt \
        mkpart ESP fat32 1MiB 1GiB set 1 esp on \
        mkpart "$rootname" ext4 1GiB 100%
      udevadm settle

      # Partition N by the kernel's naming (nvme0n1p2, mmcblk0p2, sda2), not by lsblk's order: once
      # the encrypted volume is open, lsblk can list it before the partitions and shift them.
      part() {
        case "$disk" in
          *[0-9]) echo "''${disk}p$1" ;;
          *) echo "$disk$1" ;;
        esac
      }
      mkfs.fat -F 32 -n POCKET-BOOT "$(part 1)"
      system=${boxSystem}
      recovery=""
      if [ "$tpm" = yes ]; then
        # A throwaway key opens the volume while the installer sets it up, then makes way for the
        # recovery key and the TPM.
        key=$(mktemp)
        head -c 64 /dev/urandom > "$key"
        cryptsetup luksFormat --type luks2 --batch-mode --key-file "$key" "$(part 2)"
        cryptsetup open --key-file "$key" --allow-discards "$(part 2)" pocket-root
        udevadm settle
        enroll=$(systemd-cryptenroll --unlock-key-file="$key" --recovery-key "$(part 2)" 2>&1 || true)
        recovery=$(printf '%s\n' "$enroll" | grep -oE '([cbdefghijklnrtuv]{8}-){7}[cbdefghijklnrtuv]{8}' | head -n1 || true)
        if [ -z "$recovery" ]; then
          # systemd-cryptenroll refused on some PCs: make the same kind of key (64 modhex characters)
          # with cryptsetup and tag its slot as systemd's recovery key, so the box and the TPM step
          # treat it the same.
          echo "systemd-cryptenroll said:" >&2
          printf '%s\n' "$enroll" >&2
          echo "Making the recovery key with cryptsetup instead." >&2
          recovery=$(head -c 32 /dev/urandom | od -An -tx1 -v | tr -d ' \n' | tr 0123456789abcdef cbdefghijklnrtuv \
            | sed -E 's/.{8}/&-/g; s/-$//')
          rk=$(mktemp)
          printf '%s' "$recovery" > "$rk"
          if ! cryptsetup luksAddKey --batch-mode --key-file "$key" --key-slot 1 "$(part 2)" "$rk" \
            || ! printf '{"type":"systemd-recovery","keyslots":["1"]}' | cryptsetup token import "$(part 2)"; then
            shred -u "$rk" "$key"
            echo "Making the recovery key failed." >&2
            exit 1
          fi
          shred -u "$rk"
        fi
        systemd-cryptenroll --unlock-key-file="$key" --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=password "$(part 2)"
        shred -u "$key"
        mkfs.ext4 -F -L pocket-root /dev/mapper/pocket-root
        system=${boxSystemEncrypted}
      else
        mkfs.ext4 -F -L pocket-root "$(part 2)"
      fi
      udevadm settle

      # The new partitions themselves: another disk in the PC may carry the same labels.
      root=$(part 2)
      if [ "$tpm" = yes ]; then root=/dev/mapper/pocket-root; fi
      mount "$root" /mnt
      mkdir -p /mnt/boot
      mount -o umask=077 "$(part 1)" /mnt/boot

      nixos-install --system "$system" --no-root-passwd --no-channel-copy

      # The chosen apps (none listed = every app the release has).
      if [ -n "$apps" ]; then
        install -d -m 0700 /mnt/var/lib/pocket-box
        printf '%s\n' "$apps" | jq -R . | jq -s '{apps: .}' > /mnt/var/lib/pocket-box/apps.json
      fi

      umount -R /mnt
      if [ "$tpm" = yes ]; then
        cryptsetup close pocket-root
        echo
        echo "=================================================================================="
        echo " Recovery key for this box's disk. Write it down (or scan the QR code) and keep it"
        echo " away from the box:"
        echo
        echo "   $recovery"
        echo
        qrencode -t ANSIUTF8 -m 2 "$recovery" || true
        echo
        echo " You only need it if the TPM ever refuses to unlock the disk (a new motherboard,"
        echo " a firmware reset): the box then asks for it on its screen."
        echo "=================================================================================="
        read -rp "Press Enter once it is written down. " _
      fi
      echo
      echo "Done. Remove the USB stick and reboot; then open http://pocket.local from a phone or laptop on the same network."
    '';
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  image.baseName = lib.mkForce (if lite then "pocket-box-lite-installer" else "pocket-box-installer");
  isoImage.volumeID = "POCKET_BOX";
  isoImage.storeContents = [ boxSystem boxSystemEncrypted ];

  environment.systemPackages = [ pocket-install ];

  # Screen and serial both get a shell, so headless boxes can be installed over a serial cable too.
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty0" ];

  services.getty.helpLine = lib.mkForce ''

    Pocket Box${lib.optionalString lite " Lite"} installer. Run:  sudo pocket-install
    Apps: sudo pocket-install --bundle office,media  (or --apps notes,tasks; --help lists the bundles)
  '';

  system.stateVersion = "26.11";
}
