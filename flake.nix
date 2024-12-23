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

  outputs = { self, nixpkgs, home-manager, nix-darwin, mac-app-util, ... } @ inputs: {
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
              imports = [
                ./hosts/ninezeroes/home.nix
              ];
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
      trueswiftie = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          mac-app-util.darwinModules.default
          {
            imports = [
              ./hosts/trueswiftie/configuration.nix
              ./hosts/trueswiftie/software.nix
            ];
            _module.args.self = self;
          }
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            users.users.rounak = {
              ignoreShellProgramCheck = true;
              home = "/Users/rounak";
            };
            home-manager.users.rounak = {
              imports = [
                mac-app-util.homeManagerModules.default
                ./hosts/trueswiftie/home.nix
              ];
            };
          }
        ];
      };
    };

  };

}
