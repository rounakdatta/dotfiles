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
      nixpkgs-fmt
      gradle_7
      texliveFull


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

    git = {
      enable = true;
  
      userName = "Rounak Datta";
      userEmail = "rounakdatta12@gmail.com";
      signingKey = "A04E86FD28F5A421";
  
      # Conditional configuration for ~/work directory
      extraConfig = {
        "includeIf.gitdir:~/work/" = {
          userName = "Rounak Datta";
          userEmail = "rounak@commandk.dev";
          signingKey = "A04E86FD28F5A421";
        };
      };
    };

  };
}

