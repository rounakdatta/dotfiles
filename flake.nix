{
  description = "Alexander Nixinton's dotfiles";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, ... } @ inputs: {
      # starting point of an x86_64 NixOS installation
      nixosConfigurations = {
        ninezeroes = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            {
              imports = [ ./hosts/ninezeroes/configuration.nix ];
              _module.args.self = self;
            }
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.rounak = {
                imports = [ ./hosts/ninezeroes/home.nix ];
                _module.args.self = self;
                _module.args.host = "ninezeroes";
                _module.args.inputs = inputs;
              };
            }
          ];
        };
      };

      # starting point of a user-level Nix installation on an aarch64 macOS system
      darwinConfigurations = {
        ckmac = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            {
              imports = [ 
                ./hosts/ckmac/configuration.nix
                ./hosts/ckmac/software.nix
              ];
              _module.args.self = self;
            }
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              users.users.rounak.home = "/Users/rounak";
              home-manager.users.rounak = {
                imports = [ ./hosts/ckmac/home.nix ];
              };
            }
          ];
        };
      };

    };

}
