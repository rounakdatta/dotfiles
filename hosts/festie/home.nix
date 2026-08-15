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
      # `clear`, `tput`, `reset`, `infocmp` — and, just as importantly, the
      # terminfo database none of them work without. ninezeroes and trueswiftie
      # both get this from the system underneath them; a standalone home-manager
      # profile has no system, so festie had neither the binaries nor a terminfo
      # entry for the TERM tmux hands its panes. `clear` was simply not on PATH,
      # and anything else that queries terminfo (less, fzf, vim redraw) was
      # working off defaults rather than the real terminal description.
      ncurses
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

      # configs/fish runs `atuin init fish` at startup and configs/atuin
      # restores its sync key, but neither installs the binary — ninezeroes
      # happens to carry it in its own host list, so the dependency is easy to
      # miss until every shell opens with "Unknown command: atuin".
      atuin

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

      # cloud & kubernetes. All three providers, deliberately — this used to be
      # AWS-only, on the reasoning that gcloud and azure-cli are ~1GB each and
      # should wait for something to actually need them. mic is that something:
      # festie is where it gets used most, and half of it is unusable without
      # these.
      #
      # Concretely, `mic switch <cluster>` shells out to the provider CLI to
      # fetch credentials — `gcloud container clusters get-credentials` for GKE,
      # `az aks get-credentials` for AKS — so without them every GCP and Azure
      # cluster in `mic check` can only ever show ✗, and the clusters
      # themselves are unreachable. Roughly half of Lyric's fleet is on those
      # two providers.
      awscli2
      # Nix rather than the CLI's own installer: it bundles its own Python, and
      # withExtraComponents lets the GKE auth plugin be declared instead of
      # `gcloud components install` at activation. kubectl cannot talk to a GKE
      # cluster without that plugin, so gcloud alone would get us a kubeconfig
      # we couldn't use. Same form hosts/trueswiftie already uses.
      (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
      azure-cli
      # AWS SSM, for reaching BYOC lyriclets. mic's kubeconfig fetch itself only
      # needs the plain SSM API (send-command / get-command-invocation, no
      # plugin), but `mic doctor` checks for this binary and an interactive
      # `aws ssm start-session` genuinely requires it — so having it here is the
      # difference between doctor reporting a clean bill and a permanent ○.
      ssm-session-manager-plugin
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

    # No editor bootstrap on a headless box. Doom's first-run install clones
    # and byte-compiles well over a hundred packages, and because activation
    # gates the container's startup, that delay lands squarely between a fresh
    # volume and a usable terminal. Nothing here is going to open Emacs.
    doomEmacs = {
      enable = false;
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

    # Codeman is this machine's UI, and the cases it offers are the working
    # directories you actually land in. Declared here so a rebuilt festie comes
    # up pointing at ~/personal and ~/work rather than only at
    # ~/codeman-cases/<name> — the registry behind this is runtime state on the
    # PVC, so a link made by hand does not survive being deployed elsewhere.
    codeman = {
      enable = true;
      linkedCases = {
        personal = "${config.home.homeDirectory}/personal";
        work = "${config.home.homeDirectory}/work";
        # A case of its own rather than a directory to cd into after launching:
        # Codeman starts a session in the case directory, and both the skill set
        # and the MCP servers are resolved once at startup, so changing
        # directory afterwards picks up neither. configs/claude gives this path
        # its own .mcp.json for the same reason.
        byoc = "${config.home.homeDirectory}/work/byoc";
      };
    };

    # `festie-doctor` — one command that says whether this container actually
    # converged. Worth shipping rather than remembering: the failure it detects
    # is silent by construction, and the entrypoint deliberately continues past
    # a broken activation so a healthy-looking pod proves nothing.
    festie-doctor = {
      enable = true;
    };

    # The PAT-over-HTTPS path is not deterministic on a container that boots
    # with a locked GPG key — see the option's description in configs/git. The
    # mounted SSH key needs no passphrase, so git uses that instead.
    githubOverSsh = {
      enable = true;
    };

    # configs/claude declares the notprod-lyric-deploy MCP server as
    # `command = "mic"` for ~/work, and that block is not platform-gated — so
    # it lands here too. Without this the server is declared and dead, which is
    # exactly what was happening. The laptop gets mic from the lyric-tech/mic
    # Homebrew tap instead; see configs/mic for why this host can't.
    lyric-mic = {
      enable = true;
    };
  };
}
