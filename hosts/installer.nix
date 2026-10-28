# The installer ISO. It carries the finished box system in its store, so installing needs no network:
# boot it, run `sudo pocket-install`, pick the disk, reboot.
#
# On a PC with a TPM 2.0 the root partition is encrypted (LUKS2), unlocked at boot by the TPM; the
# installer shows a recovery key once. Without a TPM, or with --no-encrypt, the disk is plain: a
# headless box could not ask anyone for a password at boot.
{ config, lib, pkgs, modulesPath, boxSystem, boxSystemEncrypted, ... }:

let
  pocket-install = pkgs.writeShellApplication {
    name = "pocket-install";
    runtimeInputs = with pkgs; [ util-linux parted dosfstools e2fsprogs coreutils gnugrep cryptsetup systemd config.system.build.nixos-install ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "Run it as root: sudo pocket-install" >&2
        exit 1
      fi
      encrypt=yes
      if [ "''${1:-}" = "--no-encrypt" ]; then
        encrypt=no
        shift
      fi

      echo "Disks:"
      lsblk -d -e 7,11 -o NAME,SIZE,MODEL,TRAN
      echo
      disk="''${1:-}"
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

      part() { lsblk -lnpo NAME "$disk" | sed -n "$(( $1 + 1 ))p"; }
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
        recovery=$(systemd-cryptenroll --unlock-key-file="$key" --recovery-key "$(part 2)" 2>&1 \
          | grep -oE '([cbdefghijklnrtuv]{8}-){7}[cbdefghijklnrtuv]{8}' | head -n1 || true)
        if [ -z "$recovery" ]; then
          echo "Making the recovery key failed." >&2
          exit 1
        fi
        systemd-cryptenroll --unlock-key-file="$key" --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=password "$(part 2)"
        shred -u "$key"
        mkfs.ext4 -F -L pocket-root /dev/mapper/pocket-root
        system=${boxSystemEncrypted}
      else
        mkfs.ext4 -F -L pocket-root "$(part 2)"
      fi
      udevadm settle

      mount /dev/disk/by-label/pocket-root /mnt
      mkdir -p /mnt/boot
      mount -o umask=077 /dev/disk/by-label/POCKET-BOOT /mnt/boot

      nixos-install --system "$system" --no-root-passwd --no-channel-copy

      umount -R /mnt
      if [ "$tpm" = yes ]; then
        cryptsetup close pocket-root
        echo
        echo "=================================================================================="
        echo " Recovery key for this box's disk. Write it down and keep it away from the box:"
        echo
        echo "   $recovery"
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

  image.baseName = lib.mkForce "pocket-box-installer";
  isoImage.volumeID = "POCKET_BOX";
  isoImage.storeContents = [ boxSystem boxSystemEncrypted ];

  environment.systemPackages = [ pocket-install ];

  # Screen and serial both get a shell, so headless boxes can be installed over a serial cable too.
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty0" ];

  services.getty.helpLine = lib.mkForce ''

    Pocket Box installer. Run:  sudo pocket-install
  '';

  system.stateVersion = "26.11";
}
