# The Pocket apps that ship on the box.
#
# Every entry builds one Go binary with its React UI embedded (see lib/mkPocketApp.nix) and runs as
# one systemd service (see modules/box.nix). `input` names the flake input that pins the source,
# `version` is what the app's version pill shows.
#
# After `nix flake update <input>` bump `version`, set the changed hash to `lib.fakeHash`, run
# `nix build .#<slug>` and paste the hash from the error.
{ lib }:
{
  core = {
    title = "Pocket Core";
    pname = "pocket-core";
    input = "pocket-core";
    version = "0.20.0";
    port = 8179;
    vendorHash = "sha256-/QD+e39BeO06DdNx166/FcRLQeA9j8EJSwpkEl/Tbdc=";
    npmDepsHash = "sha256-B6hwAJzFxJG6iSPCb/vrsQrF8lzORM95hK7vslmlGm0=";
  };

  habits = {
    title = "Pocket Habits";
    pname = "pocket-habits";
    input = "pocket-habits";
    version = "0.4.3";
    port = 8169;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-dPXEr/BzsmcLbICFgR3hHiG1/dOZ5WQmyfEMUviyUCw=";
  };

  notes = {
    title = "Pocket Notes";
    pname = "pocket-notes";
    input = "pocket-notes";
    version = "0.7.4";
    port = 8182;
    vendorHash = "sha256-UM7ZCv25k1FfOl04WsQnyY47YZQVIjJIXGAYWcj5RZM=";
    npmDepsHash = "sha256-/5yuEn1YUPoCpoqPQO6hr967U6I7PhjDU4QXEu+IH6Y=";
  };

  kitchen = {
    title = "Pocket Kitchen";
    pname = "pocket-kitchen";
    input = "pocket-kitchen";
    version = "0.5.2";
    port = 8176;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-V/EgsjDw9Ljmn1icnZmpjn/9WeSDzmMN98aBsX8lnig=";
  };
}
