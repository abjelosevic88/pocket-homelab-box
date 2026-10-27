# The system that gets installed on the box's disk. Hardware-agnostic: file systems are found by
# label, which hosts/installer.nix sets when it partitions the disk.
{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  pocket.box.enable = true;

  networking.hostName = "pocket";
  networking.useDHCP = lib.mkDefault true;
  time.timeZone = lib.mkDefault "UTC";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [
    "nvme" "xhci_pci" "ahci" "usb_storage" "uas" "sd_mod" "sdhci_pci" "virtio_pci" "virtio_blk" "virtio_scsi"
  ];
  hardware.enableRedistributableFirmware = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/pocket-root";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/POCKET-BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Console-only maintenance login until the first-boot wizard sets real credentials. SSH stays off.
  users.users.pocket = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "pocket";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Trying it out without a spare PC: `nix run .#vm`, then open http://localhost:8179.
  virtualisation.vmVariant = { config, ... }: {
    pocket.box.host = "localhost";
    virtualisation = {
      memorySize = 2048;
      cores = 2;
      diskSize = 4096;
      graphics = false;
      forwardPorts = map (port: { from = "host"; host.port = port; guest.port = port; })
        config.networking.firewall.allowedTCPPorts;
    };
  };

  system.stateVersion = "26.11";
}
