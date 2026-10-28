# Pocket AI keeps the people on the box apart: everyone but the owner works in a folder of their
# own (/var/lib/pocket-ai/people/<id>), and their agents, sign-ins and git run in a bubblewrap jail
# that shows them that folder and nothing else (pocket-homelab-ai internal/agent/jail.go). The jail
# mounts a /proc of its own, which the kernel refuses ("Mount too revealing") while
# ProtectKernelTunables over-mounts parts of the service's /proc. The service runs unprivileged, so
# that setting guards little for it; every other hardening flag stays. Tested by tests/ai-jail.nix.
{ config, lib, ... }:

lib.mkIf (config.pocket.box.enable && lib.elem "ai" config.pocket.box.apps) {
  systemd.services.pocket-ai.serviceConfig.ProtectKernelTunables = lib.mkForce false;
}
