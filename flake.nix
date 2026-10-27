{
  description = "Pocket Box: a NixOS appliance with Pocket Core and the Pocket apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # App sources, pinned in flake.lock. Each has its own entry in apps.nix.
    pocket-core = { url = "github:abjelosevic88/pocket-homelab-core"; flake = false; };
    pocket-habits = { url = "github:abjelosevic88/pocket-homelab-habit-tracker"; flake = false; };
    pocket-notes = { url = "github:abjelosevic88/pocket-homelab-notes"; flake = false; };
    pocket-kitchen = { url = "github:abjelosevic88/pocket-homelab-kitchen"; flake = false; };
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
          }) catalog;
      };

      nixosModules.default = {
        imports = [ ./modules/box.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
      };

      nixosConfigurations = {
        box = lib.nixosSystem {
          inherit system;
          modules = [ self.nixosModules.default ./hosts/box.nix ];
        };

        installer = lib.nixosSystem {
          inherit system;
          specialArgs.boxSystem = self.nixosConfigurations.box.config.system.build.toplevel;
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
