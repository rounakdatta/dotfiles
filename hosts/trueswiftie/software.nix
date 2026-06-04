{ pkgs, ... }:
{
  system.stateVersion = 5;

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
      "homebrew/cask-versions"
      "homebrew/services"
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
      "cue-lang/tap/cue"
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
