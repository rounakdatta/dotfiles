{ pkgs, ... }: {

  imports = [
    ../../configs
  ];

  home = {
    stateVersion = "23.05";

    packages = with pkgs; [
      zip
      unzip
      tmux
      spotify
      sqlite
      ripgrep
      openssl
      postgresql
      inetutils
      bind
      fzf
      difftastic
      nushell
      atuin
      mpv
      python3
      jq
      yq
      qbittorrent
      wget
      dive
      ffmpeg
      kotlin
      shellcheck
      zoom-us
      nodejs_18
      nixpkgs-fmt

      # kubernetes related packages
      kubernetes-helm
      kind

      # password store related packages
      gopass
      gopass-jsonapi
      passExtensions.pass-update

      # macOS has pbcopy/pbpaste, nevertheless
      xsel
      # getting currently playing media information
      # playerctl
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