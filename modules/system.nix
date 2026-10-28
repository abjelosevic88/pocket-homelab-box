# What the owner sets up in Pocket Core's first-run wizard (and later under Settings → This box):
# time zone, Wi-Fi, Tailscale and the console password. Core cannot change the system itself, so
# pocket-box-agent (modules/agent.py) does, behind a socket only Core's group can open.
{ config, lib, pkgs, ... }:

let
  cfg = config.pocket.box;
  socket = "/run/pocket-box-agent/agent.sock";
  agentConfig = pkgs.writeText "pocket-box-agent.json" (builtins.toJSON {
    inherit socket;
    group = "pocket-box-agent";
    state_dir = "/var/lib/pocket-box/agent";
    console_user = "pocket";
    hostname = config.networking.hostName;
    inherit (cfg) domain;
    tools = {
      timedatectl = "${pkgs.systemd}/bin/timedatectl";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      "systemd-run" = "${pkgs.systemd}/bin/systemd-run";
      nmcli = "${pkgs.networkmanager}/bin/nmcli";
      ip = "${pkgs.iproute2}/bin/ip";
      tailscale = "${config.services.tailscale.package}/bin/tailscale";
      chpasswd = "${pkgs.shadow}/bin/chpasswd";
      findmnt = "${pkgs.util-linux}/bin/findmnt";
      cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    };
  });
  agent = pkgs.writers.writePython3 "pocket-box-agent" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./agent.py);
in
{
  config = lib.mkIf cfg.enable {
    # Ethernet by DHCP and Wi-Fi joined from the wizard.
    networking.networkmanager.enable = true;
    networking.useDHCP = lib.mkDefault false;

    # Remote access, joined from the wizard (login URL or auth key).
    services.tailscale = {
      enable = true;
      openFirewall = true;
    };

    # The owner picks the zone in the wizard; until then UTC.
    time.timeZone = null;

    # The console account has no password until the owner sets one in the wizard.
    users.users.pocket = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" ];
      initialHashedPassword = lib.mkDefault "!";
    };

    users.groups.pocket-box-agent = { };

    systemd.services.pocket-box-agent = {
      description = "Pocket Box agent (system settings for Pocket Core)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      before = [ "pocket-core.service" ];
      serviceConfig = {
        ExecStart = "${agent} ${agentConfig}";
        RuntimeDirectory = "pocket-box-agent";
        RuntimeDirectoryMode = "0750";
        Group = "pocket-box-agent";
        Restart = "on-failure";
        RestartSec = 3;
        UMask = "0007";
      };
    };

    systemd.services.pocket-core = {
      wants = [ "pocket-box-agent.service" ];
      after = [ "pocket-box-agent.service" ];
      environment.BOX_AGENT = socket;
      serviceConfig.SupplementaryGroups = [ "pocket-box-agent" ];
    };
  };
}
