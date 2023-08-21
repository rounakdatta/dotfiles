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
      spotify
      nextcloud-client
      tailscale

      # password store related packages
      gopass
      gopass-jsonapi
      passExtensions.pass-update

      # copy/pasting via command line
      xsel
      # getting battery and temperature information
      acpi
      # getting currently playing media information
      playerctl
    ];
  };

  programs = {
    htop = {
      enable = true;
      settings.color_scheme = 6;
    };

    home-manager = {
      enable = true;
    };

    password-store = {
      enable = true;
    };
  };
}
