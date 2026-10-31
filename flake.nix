{
  description = "Pocket Box: a NixOS appliance with Pocket Core and the Pocket apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # App sources, pinned in flake.lock. Each has its own entry in apps.nix.
    pocket-core = { url = "github:abjelosevic88/pocket-homelab-core/v0.29.2"; flake = false; };
    pocket-ai = { url = "github:abjelosevic88/pocket-homelab-ai/v0.42.3"; flake = false; };
    pocket-alerts = { url = "github:abjelosevic88/pocket-homelab-alerts/v0.2.0"; flake = false; };
    pocket-audiobooks = { url = "github:abjelosevic88/pocket-homelab-audiobooks/v1.4.3"; flake = false; };
    pocket-backups = { url = "github:abjelosevic88/pocket-homelab-backups/v0.3.0"; flake = false; };
    pocket-blueprint = { url = "github:abjelosevic88/pocket-homelab-blueprint/v0.1.1"; flake = false; };
    pocket-bookshelf = { url = "github:abjelosevic88/pocket-homelab-bookshelf/v0.16.6"; flake = false; };
    pocket-calendar = { url = "github:abjelosevic88/pocket-homelab-calendar/v0.7.1"; flake = false; };
    pocket-clips = { url = "github:abjelosevic88/pocket-homelab-clips/v0.2.3"; flake = false; };
    pocket-contacts = { url = "github:abjelosevic88/pocket-homelab-contacts/v0.2.2"; flake = false; };
    pocket-database = { url = "github:abjelosevic88/pocket-homelab-database/v0.1.2"; flake = false; };
    pocket-day = { url = "github:abjelosevic88/pocket-homelab-day/v0.19.0"; flake = false; };
    pocket-documents = { url = "github:abjelosevic88/pocket-homelab-documents/v0.6.1"; flake = false; };
    pocket-draw = { url = "github:abjelosevic88/pocket-homelab-draw/v0.2.4"; flake = false; };
    pocket-files = { url = "github:abjelosevic88/pocket-homelab-files/v0.9.1"; flake = false; };
    pocket-flows = { url = "github:abjelosevic88/pocket-homelab-flows/v0.1.1"; flake = false; };
    pocket-garage = { url = "github:abjelosevic88/pocket-homelab-garage/v0.11.2"; flake = false; };
    pocket-guitar = { url = "github:abjelosevic88/pocket-homelab-guitar/v0.6.0"; flake = false; };
    pocket-habits = { url = "github:abjelosevic88/pocket-homelab-habit-tracker/v0.4.5"; flake = false; };
    pocket-health = { url = "github:abjelosevic88/pocket-homelab-health/v0.2.3"; flake = false; };
    pocket-horoscope = { url = "github:abjelosevic88/pocket-homelab-horoscope/v0.3.3"; flake = false; };
    pocket-hub = { url = "github:abjelosevic88/pocket-homelab-hub/v0.6.1"; flake = false; };
    pocket-inventory = { url = "github:abjelosevic88/pocket-homelab-inventory/v0.5.3"; flake = false; };
    pocket-invoicing = { url = "github:abjelosevic88/pocket-homelab-invoicing/v0.12.1"; flake = false; };
    pocket-kitchen = { url = "github:abjelosevic88/pocket-homelab-kitchen/v0.5.3"; flake = false; };
    pocket-learn = { url = "github:abjelosevic88/pocket-homelab-learn/v0.2.1"; flake = false; };
    pocket-library = { url = "github:abjelosevic88/pocket-homelab-library/v0.1.2"; flake = false; };
    pocket-mail = { url = "github:abjelosevic88/pocket-homelab-email/v0.1.2"; flake = false; };
    pocket-money = { url = "github:abjelosevic88/pocket-homelab-money/v0.17.1"; flake = false; };
    pocket-monitoring = { url = "github:abjelosevic88/pocket-homelab-monitoring/v0.4.1"; flake = false; };
    pocket-movement = { url = "github:abjelosevic88/pcket-homelab-movent/v0.3.3"; flake = false; };
    pocket-music = { url = "github:abjelosevic88/pocket-homelab-music/v0.4.2"; flake = false; };
    pocket-network = { url = "github:abjelosevic88/pocket-homelab-network/v0.1.2"; flake = false; };
    pocket-notes = { url = "github:abjelosevic88/pocket-homelab-notes/v0.8.3"; flake = false; };
    pocket-office = { url = "github:abjelosevic88/pocket-homelab-office/v0.7.0"; flake = false; };
    pocket-photos = { url = "github:abjelosevic88/pocket-homelab-photos/v0.4.1"; flake = false; };
    pocket-podcasts = { url = "github:abjelosevic88/pocket-homelab-podcasts/v0.4.3"; flake = false; };
    pocket-pr-review = { url = "github:abjelosevic88/pocket-homelab-pr-review/v0.2.0"; flake = false; };
    pocket-projects = { url = "github:abjelosevic88/pocket-homelab-projects/v0.33.0"; flake = false; };
    pocket-radio = { url = "github:abjelosevic88/pocket-homelab-radio/v0.1.0"; flake = false; };
    pocket-reader = { url = "github:abjelosevic88/pocket-homelab-reader/v0.1.1"; flake = false; };
    pocket-requests = { url = "github:abjelosevic88/pocket-homelab-requests/v0.7.1"; flake = false; };
    pocket-review = { url = "github:abjelosevic88/pocket-homelab-review/v0.6.0"; flake = false; };
    pocket-split = { url = "github:abjelosevic88/pocket-homelab-cost-split/v0.7.1"; flake = false; };
    pocket-still = { url = "github:abjelosevic88/pocket-homelab-still/v0.1.2"; flake = false; };
    pocket-subtitles = { url = "github:abjelosevic88/pocket-homelab-subtitles/v0.5.2"; flake = false; };
    pocket-tasks = { url = "github:abjelosevic88/pocket-homelab-tasks/v0.3.3"; flake = false; };
    pocket-time = { url = "github:abjelosevic88/pocket-homelab-time/v0.1.1"; flake = false; };
    pocket-travel = { url = "github:abjelosevic88/pocket-homelab-travel/v0.10.2"; flake = false; };
    pocket-watch = { url = "github:abjelosevic88/pocket-homelab-watch/v0.4.3"; flake = false; };
    pocket-wishlist = { url = "github:abjelosevic88/pocket-homelab-whishlist/v0.3.2"; flake = false; };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs { inherit system; overlays = [ self.overlays.default ]; };
      catalog = import ./apps.nix { inherit lib; };
    in
    {
      # pkgs.pocket.<slug> for every app in apps.nix.
      overlays.default = final: prev: {
        pocket = lib.mapAttrs (slug: app:
          final.callPackage ./lib/mkPocketApp.nix { } {
            inherit (app) pname version vendorHash npmDepsHash title;
            src = inputs.${app.input};
            runtime = (app.runtime or (_: [ ])) final;
            wrap = (app.wrap or (_: [ ])) final;
            postInstall = app.postInstall or "";
            npmFlags = app.npmFlags or [ ];
          }) catalog;
      };

      nixosModules.default = {
        imports = [ ./modules/box.nix ./modules/ai-sandbox.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
        # The release: the commit's date and time (UTC) and revision ("dirty" for uncommitted work).
        pocket.box.release = {
          version = let d = self.lastModifiedDate or "197001010000"; in
            "${builtins.substring 0 4 d}.${builtins.substring 4 2 d}.${builtins.substring 6 2 d}.${builtins.substring 8 4 d}";
          rev = self.shortRev or self.dirtyShortRev or "dirty";
        };
        system.configurationRevision = self.rev or self.dirtyRev or null;
      };

      nixosConfigurations = {
        box = lib.nixosSystem {
          inherit system;
          modules = [ self.nixosModules.default ./hosts/box.nix ];
        };

        # The same system on an encrypted disk (pocket-install picks it when the PC has a TPM).
        box-encrypted = self.nixosConfigurations.box.extendModules {
          modules = [ ./hosts/encrypted.nix { pocket.box.updates.variant = "box-encrypted"; } ];
        };

        installer = lib.nixosSystem {
          inherit system;
          specialArgs = {
            boxSystem = self.nixosConfigurations.box.config.system.build.toplevel;
            boxSystemEncrypted = self.nixosConfigurations.box-encrypted.config.system.build.toplevel;
          };
          modules = [ ./hosts/installer.nix ];
        };
      };

      packages.${system} = pkgs.pocket // {
        vm = self.nixosConfigurations.box.config.system.build.vm;
        iso = self.nixosConfigurations.installer.config.system.build.isoImage;
        default = self.packages.${system}.iso;
      };

      apps.${system}.vm = {
        type = "app";
        program = "${self.packages.${system}.vm}/bin/run-pocket-vm";
      };
    };
}
