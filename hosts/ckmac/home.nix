
{ pkgs, ... }: {

#   imports = [
#      ../../configs
#   ];

  home = {
    stateVersion = "23.05";
    username = "rounak";

    # host-level packages
    packages = with pkgs; [
      unzip
    ];
  };

  programs = {
    home-manager = {
        enable = true;
    };

    password-store = {
        enable = true;
    };
  };
}