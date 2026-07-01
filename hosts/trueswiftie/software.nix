{ pkgs, config, lib, ... }:
let
  # Homebrew 6 refuses to load formulae/casks from non-official ("untrusted")
  # taps unless they're explicitly trusted (https://docs.brew.sh/Tap-Trust).
  # nix-darwin's homebrew module has no trust option yet, so mirror what
  # nix-homebrew's tap-trust support does (zhaofengli/nix-homebrew#157): run
  # `brew trust <tap>` for every third-party tap this config pulls from, before
  # `brew bundle` runs (extraActivation precedes the homebrew phase) — and run it
  # AS the primary user, because activation is root and Homebrew refuses to run
  # as root (so trusting as root silently no-ops, which is why the first attempt
  # failed). This matches the user the homebrew bundle itself runs as.
  # Trusting the whole tap is appropriate here: if it's in this file, we vouch
  # for it. Tap names are lowercased to match how Homebrew normalizes them.
  tapName = t: if builtins.isString t then t else t.name;
  # "user/repo/leaf" (a fully-qualified brew/cask) -> [ "user/repo" ]; else [ ].
  qualifiedTap = s:
    let parts = lib.splitString "/" s;
    in lib.optional (builtins.length parts >= 3)
      (lib.toLower "${builtins.elemAt parts 0}/${builtins.elemAt parts 1}");
  trustedTaps = lib.unique (
    (map (t: lib.toLower (tapName t)) config.homebrew.taps)
    ++ lib.concatMap (b: qualifiedTap (tapName b)) config.homebrew.brews
    ++ lib.concatMap (c: qualifiedTap (tapName c)) config.homebrew.casks
  );
in
{
  system.stateVersion = 5;

  # Trust the declared third-party taps before `brew bundle` (see trustedTaps).
  # Guarded + best-effort so it never aborts activation (and is a no-op on a
  # brew old enough to predate the trust gate, which also lacks `brew trust`).
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    if [ -x /opt/homebrew/bin/brew ]; then
      for tap in ${lib.escapeShellArgs trustedTaps}; do
        /usr/bin/sudo -n -u ${config.system.primaryUser} -H /opt/homebrew/bin/brew trust "$tap" >/dev/null 2>&1 || true
      done
    fi
  '';

  environment = {
    # this is so that fish gets added to /etc/shells
    shells = [
      pkgs.fish
    ];

    # these are installed globally to /Applications/Nix Apps/
    systemPackages = with pkgs; [
      fish
      kitty
      tailscale
    ];
  };

  homebrew = {
    enable = true;
    # disabling quarantine would mean no stupid macOS do-you-really-want-to-open dialogs
    # caskArgs.no_quarantine = true; # no quarantine is dead
    onActivation = {
      autoUpdate = true;
      # uninstall: removes packages not listed in the config (without requiring Full Disk Access)
      # zap: more aggressive cleanup but requires Full Disk Access permissions
      cleanup = "uninstall";
      upgrade = true;
      # --force-cleanup is required because Homebrew 4.x now refuses `brew bundle
      # --cleanup` (which uninstalls casks/brews not in this file) unless an
      # explicit force flag confirms the destructive cleanup. nix-darwin appends
      # extraFlags to the bundle command, so this is the cleanest place for it.
      # Without it, a fresh laptop (which bootstraps the newest brew) aborts
      # activation with: `brew bundle install --cleanup` requires `--force` ...
      extraFlags = [ "--verbose" "--force-cleanup" ];
    };

    # taps to open, let packages rain
    taps = [
      "FairwindsOps/tap"
      "rajatjindal/tap"
      "metalbear-co/mirrord"
      "cue-lang/tap"
      {
        name = "lyric-tech/mic";
        clone_target = "git@github.com:lyric-tech/mic.git";
      }
      "guumaster/tap"
      "rana-gmbh/netfluss"
    ];

    # `brew list <>` can help pinpoint package name
    # for both ordinary packages and casks
    brews = [
      "coreutils"
      "findutils"
      "curl"
      "awscli"
      "mas"
      "pinentry-mac"
      "watch"
      "apktool"
      "node@18"
      "yarn" # the JS package manager, not the hadoop scheduler
      "azure-cli"
      "tree"
      "wimlib" # required when dealing with Windows installation archives
      {
        name = "syncthing";
        start_service = true;
        restart_service = "changed";
      }
      "go"
      "FairwindsOps/tap/rbac-lookup"
      "eksctl"
      "rajatjindal/tap/modify-secret"
      "rga" # powerful tool like ripgrep, but within files
      "colima" # lightweight container runtime
      "lima-additional-guestagents"
      "qemu" # this is required for multi-arch container builds
      "git-delta"
      "kubectl"
      "asciinema"
      "agg"
      "azcopy"
      "gemini-cli"
      "metalbear-co/mirrord/mirrord"
      "opencode"
      "gh"
      "yt-dlp"
      "oven-sh/bun/bun"
      "kubectx"
      "lyric-tech/mic/mic"
      "guumaster/tap/hostctl"
      "googleworkspace-cli"
    ];

    casks = [
      "visual-studio-code"
      "google-chrome"
      "nextcloud"
      "vlc"
      "intellij-idea-ce"
      "balenaetcher"
      "bluesnooze"
      "brave-browser"
      "chromium"
      "dbeaver-community"
      "docker-desktop"
      "firefox"
      # gcloud-cli intentionally lives in home.nix as the Nix `google-cloud-sdk`
      # package: it bundles its own Python (macOS system python 3.9 is too old
      # for gcloud) and lets us declare the gke-gcloud-auth-plugin component.
      "gpg-suite"
      "keka"
      "krita"
      "microsoft-office"
      "postman"
      "scroll-reverser"
      "slack"
      "spotify"
      "sublime-text"
      "bitwarden"
      "google-earth-pro"
      "calibre"
      "hiddenbar"
      "hammerspoon" # drives the Claude desk-pet overlay (configs/hammerspoon)
      "obsidian"
      "mongodb-compass"
      "stremio"
      "zoom"
      "cursor" # when in the AI generation, do as the generationalists do
      "steam"
      "jdownloader"
      # coding will never be the same again
      "cursor-cli"
      "zed"
      "claude-code@latest"
      "claude"
      "codex"
      "codex-app"
      "antigravity"
      "cap"
      "temurin@21"
      "zulu@8" # native arm64 Java 8 for legacy Swing apps like the TDS RPU; temurin@8 is Intel-only
      "android-commandlinetools"
      "flutter"
      "handy" # fast, fast STT
      "whatsapp"
      "vysor"
      {
        name = "llamabarn";
        args = {
          appdir = "~/Applications";
        };
      } # r/LocalLLaMA ftw
      "google-drive"
      "rana-gmbh/netfluss/netfluss"
      "alienator88-sentinel"
      "supercmdlabs/supercmd/supercmd"
    ];

    # `mas search <>` can help pinpoint package name
    masApps = { };

  };
}
