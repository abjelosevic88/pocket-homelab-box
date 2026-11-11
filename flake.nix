{
  description = "Pocket Box: a NixOS appliance with Pocket Core and the Pocket apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # App sources, pinned in flake.lock. Each has its own entry in apps.nix.
    pocket-core = { url = "github:abjelosevic88/pocket-homelab-core/v0.36.24"; flake = false; };
    pocket-ai = { url = "github:abjelosevic88/pocket-homelab-ai/v0.88.5"; flake = false; };
    pocket-alerts = { url = "github:abjelosevic88/pocket-homelab-alerts/v0.2.1"; flake = false; };
    pocket-audiobooks = { url = "github:abjelosevic88/pocket-homelab-audiobooks/v1.6.1"; flake = false; };
    pocket-backups = { url = "github:abjelosevic88/pocket-homelab-backups/v0.3.1"; flake = false; };
    pocket-blog = { url = "github:abjelosevic88/pocket-homelab-blog/v0.1.2"; flake = false; };
    pocket-blueprint = { url = "github:abjelosevic88/pocket-homelab-blueprint/v0.2.0"; flake = false; };
    pocket-boards = { url = "github:abjelosevic88/pocket-homelab-boards/v0.1.3"; flake = false; };
    pocket-bookshelf = { url = "github:abjelosevic88/pocket-homelab-bookshelf/v0.23.0"; flake = false; };
    pocket-calendar = { url = "github:abjelosevic88/pocket-homelab-calendar/v0.7.4"; flake = false; };
    pocket-chat = { url = "github:abjelosevic88/pocket-homelab-chat/v0.2.3"; flake = false; };
    pocket-clips = { url = "github:abjelosevic88/pocket-homelab-clips/v0.2.4"; flake = false; };
    pocket-contacts = { url = "github:abjelosevic88/pocket-homelab-contacts/v0.6.0"; flake = false; };
    pocket-crm = { url = "github:abjelosevic88/pocket-homelab-crm/v0.1.1"; flake = false; };
    pocket-database = { url = "github:abjelosevic88/pocket-homelab-database/v0.1.4"; flake = false; };
    pocket-day = { url = "github:abjelosevic88/pocket-homelab-day/v0.40.0"; flake = false; };
    pocket-documents = { url = "github:abjelosevic88/pocket-homelab-documents/v0.8.4"; flake = false; };
    pocket-draw = { url = "github:abjelosevic88/pocket-homelab-draw/v0.4.1"; flake = false; };
    pocket-errors = { url = "github:abjelosevic88/pocket-homelab-errors/v0.1.1"; flake = false; };
    pocket-family = { url = "github:abjelosevic88/pocket-homelab-family/v0.1.1"; flake = false; };
    pocket-files = { url = "github:abjelosevic88/pocket-homelab-files/v0.13.1"; flake = false; };
    pocket-fitness = { url = "github:abjelosevic88/pocket-homelab-fitness/v0.1.1"; flake = false; };
    pocket-flows = { url = "github:abjelosevic88/pocket-homelab-flows/v0.7.0"; flake = false; };
    pocket-forms = { url = "github:abjelosevic88/pocket-homelab-forms/v0.2.0"; flake = false; };
    pocket-games = { url = "github:abjelosevic88/pocket-homelab-games/v0.2.4"; flake = false; };
    pocket-garage = { url = "github:abjelosevic88/pocket-homelab-garage/v0.11.6"; flake = false; };
    pocket-guitar = { url = "github:abjelosevic88/pocket-homelab-guitar/v0.6.3"; flake = false; };
    pocket-habits = { url = "github:abjelosevic88/pocket-homelab-habit-tracker/v0.4.7"; flake = false; };
    pocket-health = { url = "github:abjelosevic88/pocket-homelab-health/v0.5.1"; flake = false; };
    pocket-home = { url = "github:abjelosevic88/pocket-homelab-home/v0.3.0"; flake = false; };
    pocket-horoscope = { url = "github:abjelosevic88/pocket-homelab-horoscope/v0.3.5"; flake = false; };
    pocket-hub = { url = "github:abjelosevic88/pocket-homelab-hub/v0.6.6"; flake = false; };
    pocket-inventory = { url = "github:abjelosevic88/pocket-homelab-inventory/v0.5.5"; flake = false; };
    pocket-invoicing = { url = "github:abjelosevic88/pocket-homelab-invoicing/v0.14.0"; flake = false; };
    pocket-jobs = { url = "github:abjelosevic88/pocket-homelab-jobs/v0.1.0"; flake = false; };
    pocket-kitchen = { url = "github:abjelosevic88/pocket-homelab-kitchen/v0.6.0"; flake = false; };
    pocket-league = { url = "github:abjelosevic88/pocket-homelab-league/v0.4.6"; flake = false; };
    pocket-learn = { url = "github:abjelosevic88/pocket-homelab-learn/v0.2.3"; flake = false; };
    pocket-library = { url = "github:abjelosevic88/pocket-homelab-library/v0.11.0"; flake = false; };
    pocket-lookout = { url = "github:abjelosevic88/pocket-homelab-lookout/v0.2.2"; flake = false; };
    pocket-mail = { url = "github:abjelosevic88/pocket-homelab-email/v0.3.0"; flake = false; };
    pocket-map = { url = "github:abjelosevic88/pocket-homelab-map/v0.1.0"; flake = false; };
    pocket-money = { url = "github:abjelosevic88/pocket-homelab-money/v0.22.8"; flake = false; };
    pocket-monitoring = { url = "github:abjelosevic88/pocket-homelab-monitoring/v0.6.3"; flake = false; };
    pocket-movement = { url = "github:abjelosevic88/pcket-homelab-movent/v0.3.5"; flake = false; };
    pocket-music = { url = "github:abjelosevic88/pocket-homelab-music/v0.8.1"; flake = false; };
    pocket-network = { url = "github:abjelosevic88/pocket-homelab-network/v0.1.4"; flake = false; };
    pocket-notes = { url = "github:abjelosevic88/pocket-homelab-notes/v0.11.1"; flake = false; };
    pocket-nutrition = { url = "github:abjelosevic88/pocket-homelab-nutrition/v0.1.0"; flake = false; };
    pocket-office = { url = "github:abjelosevic88/pocket-homelab-office/v0.7.2"; flake = false; };
    pocket-parcels = { url = "github:abjelosevic88/pocket-homelab-parcels/v0.1.1"; flake = false; };
    pocket-pets = { url = "github:abjelosevic88/pocket-homelab-pets/v0.1.1"; flake = false; };
    pocket-photos = { url = "github:abjelosevic88/pocket-homelab-photos/v0.6.1"; flake = false; };
    pocket-places = { url = "github:abjelosevic88/pocket-homelab-places/v0.1.2"; flake = false; };
    pocket-podcasts = { url = "github:abjelosevic88/pocket-homelab-podcasts/v0.4.5"; flake = false; };
    pocket-pr-review = { url = "github:abjelosevic88/pocket-homelab-pr-review/v0.3.0"; flake = false; };
    pocket-projects = { url = "github:abjelosevic88/pocket-homelab-projects/v0.40.2"; flake = false; };
    pocket-radio = { url = "github:abjelosevic88/pocket-homelab-radio/v0.1.2"; flake = false; };
    pocket-reader = { url = "github:abjelosevic88/pocket-homelab-reader/v0.1.2"; flake = false; };
    pocket-remote = { url = "github:abjelosevic88/pocket-homelab-remote/v0.3.0"; flake = false; };
    pocket-renewals = { url = "github:abjelosevic88/pocket-homelab-renewals/v0.6.0"; flake = false; };
    pocket-rentals = { url = "github:abjelosevic88/pocket-homelab-rentals/v0.1.1"; flake = false; };
    pocket-requests = { url = "github:abjelosevic88/pocket-homelab-requests/v0.9.1"; flake = false; };
    pocket-review = { url = "github:abjelosevic88/pocket-homelab-review/v0.7.0"; flake = false; };
    pocket-search = { url = "github:abjelosevic88/pocket-homelab-search/v0.14.0"; flake = false; };
    pocket-sign = { url = "github:abjelosevic88/pocket-homelab-sign/v0.1.0"; flake = false; };
    pocket-split = { url = "github:abjelosevic88/pocket-homelab-cost-split/v0.7.2"; flake = false; };
    pocket-sphere = { url = "github:abjelosevic88/pocket-homelab-sphere/v0.5.0"; flake = false; };
    pocket-still = { url = "github:abjelosevic88/pocket-homelab-still/v0.1.4"; flake = false; };
    pocket-subtitles = { url = "github:abjelosevic88/pocket-homelab-subtitles/v0.6.1"; flake = false; };
    pocket-tables = { url = "github:abjelosevic88/pocket-homelab-tables/v0.2.0"; flake = false; };
    pocket-tasks = { url = "github:abjelosevic88/pocket-homelab-tasks/v0.5.2"; flake = false; };
    pocket-time = { url = "github:abjelosevic88/pocket-homelab-time/v0.1.4"; flake = false; };
    pocket-trails = { url = "github:abjelosevic88/pocket-homelab-trails/v0.1.4"; flake = false; };
    pocket-translate = { url = "github:abjelosevic88/pocket-homelab-translate/v0.1.3"; flake = false; };
    pocket-travel = { url = "github:abjelosevic88/pocket-homelab-travel/v0.13.0"; flake = false; };
    pocket-voice = { url = "github:abjelosevic88/pocket-homelab-voice/v0.7.12"; flake = false; };
    pocket-wallet = { url = "github:abjelosevic88/pocket-homelab-wallet/v0.1.0"; flake = false; };
    pocket-wardrobe = { url = "github:abjelosevic88/pocket-homelab-wardrobe/v0.1.3"; flake = false; };
    pocket-watch = { url = "github:abjelosevic88/pocket-homelab-watch/v0.5.3"; flake = false; };
    pocket-wealth = { url = "github:abjelosevic88/pocket-homelab-wealth/v0.2.0"; flake = false; };
    pocket-weather = { url = "github:abjelosevic88/pocket-homelab-weather/v0.3.0"; flake = false; };
    pocket-wishlist = { url = "github:abjelosevic88/pocket-homelab-whishlist/v0.4.4"; flake = false; };
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

      checks.${system}.engines = import ./tests/engines.nix { inherit self pkgs; };

      apps.${system}.vm = {
        type = "app";
        program = "${self.packages.${system}.vm}/bin/run-pocket-vm";
      };
    };
}
