{ config, pkgs, user, ... }: {

  imports = [
    ../../configs
  ];

  home = {
    stateVersion = "23.05";
    username = user.username;
    homeDirectory = "/home/${user.username}";

    # Host-level packages, deliberately CLI-only. festie is a container, so
    # there is no base system underneath it and nothing that could render a
    # GUI — everything graphical that ninezeroes carries (kitty, vscode,
    # chrome, spotify, vlc, krita, ...) is intentionally absent, as is
    # texliveFull. The image has to stay small enough to pull onto the homelab
    # quickly, and every one of these has to justify its closure.
    packages = with pkgs; [
      # core userland — a Nix container ships with none of this
      coreutils
      findutils
      diffutils
      gnugrep
      gnused
      gawk
      gnutar
      gzip
      which
      less
      procps
      zip
      unzip
      # TLS trust store; the image entrypoint points SSL_CERT_FILE at this
      cacert

      # version control (git and tmux themselves come from ../../configs)
      gh
      git-lfs
      difftastic

      # search & navigation
      ripgrep
      fd
      fzf
      tree

      # data wrangling
      jq
      yq

      # network
      curl
      wget
      openssh
      openssl
      inetutils # telnet, ping, ...
      bind # dig, ...

      # cloud & kubernetes. Only AWS for now — gcloud and azure-cli are each
      # roughly a gigabyte, so they get added the day something actually needs
      # them rather than on the off chance.
      awscli2
      kubectl
      kubernetes-helm
      kustomize

      # languages & runtimes
      python3
      nodejs
      go

      # misc dev
      shellcheck
      nixpkgs-fmt
      sqlite

      # secrets — configs/pass and configs/gopass expect these to exist
      gnupg
      gopass
      passExtensions.pass-update
    ];
  };

  # The GPG key is passphrase-protected, and on a headless box that is the
  # difference between pass/gopass working and silently failing — including the
  # MCP servers that shell out to `pass show`.
  services.gpg-agent = {
    # pinentry-gnome3 has no display to draw on here, so the first decryption
    # would fail with no way to prompt. curses draws inside whatever tty is
    # asking, which is the tmux pane Codeman hands you.
    pinentry.package = pkgs.pinentry-curses;

    # Unlock once per container, not once every ten minutes. This machine is
    # meant to keep working while nobody is watching it, and a cache that
    # expires mid-run turns into an agent stuck on an invisible prompt.
    # 400 days; the practical lifetime is the pod's, since ~/.gnupg's agent
    # dies with it.
    defaultCacheTtl = 34560000;
    maxCacheTtl = 34560000;

    # No systemd user session in a container, so the agent's ssh socket never
    # comes up. ssh uses the explicit IdentityFile from configs/ssh instead,
    # and pointing SSH_AUTH_SOCK at a socket that will never exist only
    # produces confusing failures.
    enableSshSupport = false;
  };

  programs = {
    home-manager = {
      enable = true;
    };

    htop = {
      enable = true;
      settings.color_scheme = 6;
    };

    password-store = {
      enable = true;
    };

    # Carried over from the laptop verbatim, so the agent gets the same skills
    # it has locally. Note that this makes container startup depend on an SSH
    # key that can read the agent-smith repo: the sync runs as a home-manager
    # activation step and `git clone` there is not fault-tolerant, so a missing
    # key fails activation rather than degrading. Flip to false for a first
    # smoke test if the key isn't mounted yet.
    claude-skills = {
      enablePrivate = true;
      privateRepo.url = "git@github.com:rounakdatta/agent-smith.git";
    };
  };
}
