# The system that gets installed on the box's disk. Hardware-agnostic: file systems are found by
# label, which hosts/installer.nix sets when it partitions the disk.
{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  pocket.box.enable = true;

  networking.hostName = "pocket";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [
    "nvme" "xhci_pci" "ahci" "usb_storage" "uas" "sd_mod" "sdhci_pci" "virtio_pci" "virtio_blk" "virtio_scsi"
  ];
  hardware.enableRedistributableFirmware = true;
  # A console on the screen and on the first serial port, for boxes without a screen.
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty0" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/pocket-root";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/POCKET-BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # The console account "pocket" (modules/system.nix) stays locked until the setup wizard sets its
  # password. SSH stays off.

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Trying it out without a spare PC: `nix run .#vm`, then open http://pocket.localhost:8080 for the
  # certificate and https://core.pocket.localhost:8443 (browsers send *.localhost to this machine).
  virtualisation.vmVariant = { config, ... }: {
    # A known console password for development.
    users.users.pocket.initialHashedPassword = lib.mkForce null;
    users.users.pocket.initialPassword = "pocket";
    pocket.box = {
      domain = "pocket.localhost";
      httpsPort = 8443;
      httpPort = 8080;
    };
    virtualisation = {
      memorySize = 6144;
      cores = 2;
      diskSize = 8192;
      graphics = false;
      forwardPorts = map (port: { from = "host"; host.port = port; guest.port = port; })
        config.networking.firewall.allowedTCPPorts;
    };
  };

  system.stateVersion = "26.11";
}
