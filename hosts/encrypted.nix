# The installed system when the disk is encrypted (pocket-install does this on a box with a TPM 2.0).
# The root partition is LUKS2, opened at boot by the TPM — bound to the firmware's Secure Boot
# state (PCR 7), so kernel and app updates do not lock it — or, if that ever fails, by the
# recovery key the installer showed, typed at the box's screen.
{ ... }:

{
  boot.initrd.systemd.tpm2.enable = true;
  boot.initrd.availableKernelModules = [ "tpm_crb" "tpm_tis" ];
  boot.initrd.luks.devices.pocket-root = {
    device = "/dev/disk/by-partlabel/pocket-crypt";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
    allowDiscards = true;
  };
}
