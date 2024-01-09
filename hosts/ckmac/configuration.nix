{ inputs, config, pkgs, ... }:

{
  nix.settings = {
    # this is required because flakes hasn't graduated into a stable feature yet
    experimental-features = [ "nix-command" "flakes" ];
  };

  services.nix-daemon.enable = true;

  networking.hostName = "ckmac";

  programs.fish.enable = true;
  users.users.rounak = {
    # workaround for https://github.com/nix-community/home-manager/issues/4026
    home = "/Users/rounak";
    description = "Rounak";
    packages = with pkgs; [
      git
      vim
      kitty
    ];
    shell = pkgs.fish;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}