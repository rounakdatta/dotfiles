
{ pkgs, ... }: {

  imports = [
     ../../configs/git
  ];

  home = {
    stateVersion = "23.05";
    username = "rounak";

    # packages that need to be installed through Nix packages
    # they should be searched and verified on https://search.nixos.org/packages
    # this list is populated keeping aarch64 in mind
    packages = with pkgs; [
      zip
      unzip
      tmux
      vscode
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
      qutebrowser
      zoom-us

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