{ pkgs, ... }: {

  imports = [
     ../../configs
  ];

  home = {
    stateVersion = "23.05";
    username = "rounak";
    homeDirectory = "/home/rounak";

    # host-level packages
    packages = with pkgs; [
      unzip
      vscode
      google-chrome
      gopass
      gopass-jsonapi
    ];
  };

  programs = {
    htop = {
      enable = true;
      settings.color_scheme = 1;
    };

    home-manager = {
      enable = true;
    };

    password-store = {
      enable = true;
    };
  };
}
