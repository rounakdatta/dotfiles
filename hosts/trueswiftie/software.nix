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
    ];
  };

  homebrew = {
    enable = true;
    # disabling quarantine would mean no stupid macOS do-you-really-want-to-open dialogs
    caskArgs.no_quarantine = true;
    onActivation = {
      autoUpdate = true;
      # uninstall: removes packages not listed in the config (without requiring Full Disk Access)
      # zap: more aggressive cleanup but requires Full Disk Access permissions
      cleanup = "uninstall";
      upgrade = true;
      extraFlags = [ "--verbose" ];
    };

    # taps to open, let packages rain
    taps = [
      "homebrew/cask-versions"
      "homebrew/services"
      "FairwindsOps/tap"
      "rajatjindal/tap"
      "metalbear-co/mirrord"
      "cue-lang/tap"
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
      "docker"
      "firefox"
      "google-cloud-sdk"
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
      "claude-code"
      "codex"
      "antigravity"
      "cap"
      "temurin@21"
      "android-commandlinetools"
      "flutter"
    ];

    # `mas search <>` can help pinpoint package name
    masApps = {
      "Tailscale" = 1475387142; # Tailscale does have a brew package, however this is slightly more complete
      "Bandwidth+" = 490461369;
    };
  };
}
