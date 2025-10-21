{ pkgs, lib, ... }: {

  imports = [
    ../../configs
    ./npm-packages.nix
  ];

  home = {
    stateVersion = "23.05";

    packages = with pkgs; [
      coreutils
      zip
      unzip
      tmux
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
      shellcheck
      nixpkgs-fmt
      texliveFull
      pyenv
      poppler

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

      # coding will never be the same again
      claude-code
    ];
  };

  # Ensure GNU coreutils (readlink -e) is used during Home Manager activation
  home.activation.prependCoreutils = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    export PATH=${pkgs.coreutils}/bin:$PATH
  '';

  # Ensure scripts that call `find -printf` get GNU find on macOS
  home.activation.prependGNUFind = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    export PATH=${pkgs.writeShellScriptBin "find" ''
      exec /opt/homebrew/bin/gfind "$@"
    ''}/bin:$PATH
  '';

  # Ensure scripts that call `readlink -e` get GNU readlink on macOS
  home.activation.prependGNUReadlink = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    export PATH=${pkgs.writeShellScriptBin "readlink" ''
      exec /opt/homebrew/bin/greadlink "$@"
    ''}/bin:$PATH
  '';

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

