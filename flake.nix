{
  description = "Pocket Box: a NixOS appliance with Pocket Core and the Pocket apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # App sources, pinned in flake.lock. Each has its own entry in apps.nix.
    pocket-core = { url = "github:abjelosevic88/pocket-homelab-core"; flake = false; };
    pocket-ai = { url = "github:abjelosevic88/pocket-homelab-ai"; flake = false; };
    pocket-audiobooks = { url = "github:abjelosevic88/pocket-homelab-audiobooks"; flake = false; };
    pocket-backups = { url = "github:abjelosevic88/pocket-homelab-backups"; flake = false; };
    pocket-bookshelf = { url = "github:abjelosevic88/pocket-homelab-bookshelf"; flake = false; };
    pocket-calendar = { url = "github:abjelosevic88/pocket-homelab-calendar"; flake = false; };
    pocket-clips = { url = "github:abjelosevic88/pocket-homelab-clips"; flake = false; };
    pocket-contacts = { url = "github:abjelosevic88/pocket-homelab-contacts"; flake = false; };
    pocket-database = { url = "github:abjelosevic88/pocket-homelab-database"; flake = false; };
    pocket-day = { url = "github:abjelosevic88/pocket-homelab-day"; flake = false; };
    pocket-documents = { url = "github:abjelosevic88/pocket-homelab-documents"; flake = false; };
    pocket-files = { url = "github:abjelosevic88/pocket-homelab-files"; flake = false; };
    pocket-garage = { url = "github:abjelosevic88/pocket-homelab-garage"; flake = false; };
    pocket-habits = { url = "github:abjelosevic88/pocket-homelab-habit-tracker"; flake = false; };
    pocket-health = { url = "github:abjelosevic88/pocket-homelab-health"; flake = false; };
    pocket-hub = { url = "github:abjelosevic88/pocket-homelab-hub"; flake = false; };
    pocket-inventory = { url = "github:abjelosevic88/pocket-homelab-inventory"; flake = false; };
    pocket-invoicing = { url = "github:abjelosevic88/pocket-homelab-invoicing"; flake = false; };
    pocket-kitchen = { url = "github:abjelosevic88/pocket-homelab-kitchen"; flake = false; };
    pocket-library = { url = "github:abjelosevic88/pocket-homelab-library"; flake = false; };
    pocket-mail = { url = "github:abjelosevic88/pocket-homelab-email"; flake = false; };
    pocket-money = { url = "github:abjelosevic88/pocket-homelab-money"; flake = false; };
    pocket-monitoring = { url = "github:abjelosevic88/pocket-homelab-monitoring"; flake = false; };
    pocket-movement = { url = "github:abjelosevic88/pcket-homelab-movent"; flake = false; };
    pocket-music = { url = "github:abjelosevic88/pocket-homelab-music"; flake = false; };
    pocket-network = { url = "github:abjelosevic88/pocket-homelab-network"; flake = false; };
    pocket-notes = { url = "github:abjelosevic88/pocket-homelab-notes"; flake = false; };
    pocket-office = { url = "github:abjelosevic88/pocket-homelab-office"; flake = false; };
    pocket-photos = { url = "github:abjelosevic88/pocket-homelab-photos"; flake = false; };
    pocket-podcasts = { url = "github:abjelosevic88/pocket-homelab-podcasts"; flake = false; };
    pocket-projects = { url = "github:abjelosevic88/pocket-homelab-projects"; flake = false; };
    pocket-review = { url = "github:abjelosevic88/pocket-homelab-review"; flake = false; };
    pocket-split = { url = "github:abjelosevic88/pocket-homelab-cost-split"; flake = false; };
    pocket-still = { url = "github:abjelosevic88/pocket-homelab-still"; flake = false; };
    pocket-subtitles = { url = "github:abjelosevic88/pocket-homelab-subtitles"; flake = false; };
    pocket-tasks = { url = "github:abjelosevic88/pocket-homelab-tasks"; flake = false; };
    pocket-travel = { url = "github:abjelosevic88/pocket-homelab-travel"; flake = false; };
    pocket-watch = { url = "github:abjelosevic88/pocket-homelab-watch"; flake = false; };
    pocket-wishlist = { url = "github:abjelosevic88/pocket-homelab-whishlist"; flake = false; };
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
          }) catalog;
      };

      nixosModules.default = {
        imports = [ ./modules/box.nix ./modules/ai-sandbox.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
      };

      nixosConfigurations = {
        box = lib.nixosSystem {
          inherit system;
          modules = [ self.nixosModules.default ./hosts/box.nix ];
        };

        # The same system on an encrypted disk (pocket-install picks it when the PC has a TPM).
        box-encrypted = self.nixosConfigurations.box.extendModules { modules = [ ./hosts/encrypted.nix ]; };

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
