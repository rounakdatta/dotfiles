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

    # this is a quick util a good GitHub samaritan wrote to solve for
    # https://github.com/nix-community/home-manager/issues/1341#issuecomment-1791545015
    mac-app-util = {
      url = "github:hraban/mac-app-util";
    };
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, mac-app-util, ... } @ inputs:
  let
    user = import ./lib/user.nix;
  in
  {
    # starting point of an x86_64 NixOS installation
    nixosConfigurations = {
      ninezeroes = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs self user; };
        modules = [
          ./hosts/ninezeroes/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${user.username} = {
              imports = [ ./hosts/ninezeroes/home.nix ];
            };
          }
        ];
      };
    };

    # starting point of a user-level Nix installation on an aarch64 macOS system
    darwinConfigurations = {
      trueswiftie = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs self user; };
        modules = [
          mac-app-util.darwinModules.default
          ./hosts/trueswiftie/configuration.nix
          ./hosts/trueswiftie/software.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Automatically backup conflicting files with .backup extension
            home-manager.backupFileExtension = "backup";
            home-manager.users.${user.username} = {
              imports = [
                mac-app-util.homeManagerModules.default
                ./hosts/trueswiftie/home.nix
              ];
            };
          }
        ];
      };
    };

    checks = {
      x86_64-linux = {
        nixos = self.nixosConfigurations.ninezeroes.config.system.build.toplevel;
      };
      aarch64-darwin = {
        darwin = self.darwinConfigurations.trueswiftie.system;
      };
    };
  };
}
