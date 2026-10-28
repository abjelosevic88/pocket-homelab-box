# The installer ISO. It carries the finished box system in its store, so installing needs no network:
# boot it, run `sudo pocket-install`, pick the disk, reboot.
{ config, lib, pkgs, modulesPath, boxSystem, ... }:

let
  pocket-install = pkgs.writeShellApplication {
    name = "pocket-install";
    runtimeInputs = with pkgs; [ util-linux parted dosfstools e2fsprogs coreutils config.system.build.nixos-install ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "Run it as root: sudo pocket-install" >&2
        exit 1
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

      echo
      echo "EVERYTHING on $disk will be erased."
      read -rp "Type the disk name again to continue: " again
      if [ "/dev/''${again#/dev/}" != "$disk" ]; then
        echo "Names differ, nothing was changed." >&2
        exit 1
      fi

      umount -R /mnt 2>/dev/null || true
      wipefs -af "$disk"
      parted -s "$disk" -- mklabel gpt \
        mkpart ESP fat32 1MiB 1GiB set 1 esp on \
        mkpart root ext4 1GiB 100%
      udevadm settle

      part() { lsblk -lnpo NAME "$disk" | sed -n "$(( $1 + 1 ))p"; }
      mkfs.fat -F 32 -n POCKET-BOOT "$(part 1)"
      mkfs.ext4 -F -L pocket-root "$(part 2)"
      udevadm settle

      mount /dev/disk/by-label/pocket-root /mnt
      mkdir -p /mnt/boot
      mount -o umask=077 /dev/disk/by-label/POCKET-BOOT /mnt/boot

      nixos-install --system ${boxSystem} --no-root-passwd --no-channel-copy

      echo
      echo "Done. Remove the USB stick and reboot; then open http://pocket.local from a phone or laptop on the same network."
    '';
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  image.baseName = lib.mkForce "pocket-box-installer";
  isoImage.volumeID = "POCKET_BOX";
  isoImage.storeContents = [ boxSystem ];

  environment.systemPackages = [ pocket-install ];

  # Screen and serial both get a shell, so headless boxes can be installed over a serial cable too.
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty0" ];

  services.getty.helpLine = lib.mkForce ''

    Pocket Box installer. Run:  sudo pocket-install
  '';

  system.stateVersion = "26.11";
}
