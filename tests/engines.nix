# The two loopback helpers of modules/services.nix with their apps on the box: SearXNG answers
# Pocket Search in JSON, and Pocket Lookout opens a page in the headless Chromium.
#
#   nix build -L .#checks.x86_64-linux.engines
{ self, pkgs }:

pkgs.testers.runNixOSTest {
  name = "pocket-box-engines";
  # The box module brings its own overlay (pkgs.pocket).
  node.pkgsReadOnly = false;
  nodes.box = { lib, ... }: {
    imports = [ self.nixosModules.default ];
    pocket.box = {
      enable = true;
      domain = "pocket.test";
      apps = [ "search" "lookout" ];
      services = { jellyfin.enable = false; navidrome.enable = false; immich.enable = false; onlyoffice.enable = false; };
    };
    # The test fetches a page on the box itself, which Lookout refuses by default.
    systemd.services.pocket-lookout.environment.FETCH_PRIVATE = "true";
    virtualisation = { memorySize = 3072; cores = 2; diskSize = 4096; };
  };

  testScript = ''
    import json

    box.start()
    for unit in ["searx.service", "pocket-box-browser.service", "pocket-search.service", "pocket-lookout.service"]:
        box.wait_for_unit(unit)
    box.wait_for_open_port(8888)
    box.wait_for_open_port(9222)

    with subtest("SearXNG answers in JSON on loopback only"):
        out = json.loads(box.succeed("curl -sf 'http://127.0.0.1:8888/search?q=pocket&format=json'"))
        assert out["query"] == "pocket", out
        box.fail("ss -ltnH | grep -E ':(8888|9222) ' | grep -v 127.0.0.1")

    with subtest("Pocket Search is up with its engine"):
        box.wait_until_succeeds("curl -sf http://127.0.0.1:8225/healthz")

    with subtest("Chromium answers the DevTools protocol"):
        print(box.succeed("curl -sf http://127.0.0.1:9222/json/version"))

    with subtest("Lookout opens a page in the browser"):
        box.wait_until_succeeds("curl -sf http://127.0.0.1:8224/healthz")
        jar = "-c /tmp/jar -b /tmp/jar"
        box.succeed(
            f"curl -sf {jar} -H 'Content-Type: application/json' "
            "-d '{\"email\":\"owner@example.com\",\"password\":\"pocket-box-test\",\"name\":\"Owner\"}' "
            "http://localhost:8224/api/v1/auth/setup"
        )
        out = json.loads(box.succeed(
            f"curl -sf {jar} -H 'Content-Type: application/json' "
            "-d '{\"url\":\"http://127.0.0.1:8888/\",\"fetch_mode\":\"browser\",\"browser_wait\":1}' "
            "http://localhost:8224/api/v1/preview"
        ))
        print(json.dumps(out)[:2000])
        assert "Pocket Search engine" in json.dumps(out), out
  '';
}
