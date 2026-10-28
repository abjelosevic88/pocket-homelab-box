# Pocket AI's people jail under the Pocket AI service's hardening (modules/box.nix plus
# modules/ai-sandbox.nix): a person's process sees only their own folder, none of the service's
# data or environment and no one else's processes, and Codex starts in there.
#
#   cd ~/Projects/pocket-homelab-ai && CGO_ENABLED=0 go test -c -o /tmp/agent.test ./internal/agent
#   nix build --impure -L --expr '(import ./tests/ai-jail.nix { probe = /tmp/agent.test; })'
{ probe }:
let
  box = builtins.getFlake (toString ./..);
  pkgs = import box.inputs.nixpkgs { system = "x86_64-linux"; };
  probeDrv = pkgs.runCommand "pocket-ai-jail-probe" { } "install -Dm755 ${probe} $out/bin/agent.test";
in
pkgs.testers.runNixOSTest {
  name = "pocket-ai-jail";
  nodes.box = { pkgs, ... }: {
    systemd.services.pocket-ai-jail = {
      path = with pkgs; [ bubblewrap coreutils bash gnugrep procps codex ];
      environment = {
        DATA_DIR = "/var/lib/pocket-ai";
        HOME = "/var/lib/pocket-ai";
        POCKET_JAIL_E2E = "/var/lib/pocket-ai/people";
        POCKET_JAIL_E2E_CLI = "codex";
      };
      # the same as modules/box.nix gives an app (DynamicUser, not root), with ai-sandbox.nix
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${probeDrv}/bin/agent.test -test.run '^TestJailE2E$' -test.v";
        DynamicUser = true;
        StateDirectory = "pocket-ai";
        StateDirectoryMode = "0750";
        WorkingDirectory = "/var/lib/pocket-ai";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectKernelTunables = false;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
      };
    };
  };
  testScript = ''
    box.wait_for_unit("multi-user.target")
    _, out = box.execute("systemctl start pocket-ai-jail.service; journalctl -u pocket-ai-jail --no-pager -o cat")
    print(out)
    assert "--- PASS: TestJailE2E" in out, "the jail test did not pass"
  '';
}
