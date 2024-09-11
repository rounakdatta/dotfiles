{ pkgs, ... }: {

  environment = {
    loginShell = pkgs.fish;

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
      # zap is a more thorough uninstall, ref: https://docs.brew.sh/Cask-Cookbook#stanza-zap
      cleanup = "zap";
      upgrade = true;
      extraFlags = [ "--verbose" ];
    };

    # taps to open, let packages rain
    taps = [
      "d12frosted/emacs-plus"
      "pulumi/tap"
      "homebrew/cask-versions"
      "homebrew/services"
    ];

    # `brew list <>` can help pinpoint package name
    # for both ordinary packages and casks
    brews = [
      "fish"
      "curl"
      "awscli"
      "d12frosted/emacs-plus/emacs-plus"
      "mas"
      "pinentry-mac"
      "pulumi/tap/pulumi"
      "skaffold"
      "watch"
      "node@18"
      "yarn" # the JS package manager, not the hadoop scheduler
      "azure-cli"
      "ollama"
      "tree"
      "terraform"
      "kubeseal"
      "wimlib" # required when dealing with Windows installation archives
      {
        name = "syncthing";
        start_service = true;
        restart_service = "changed";
      }
      "go"
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
      "send-to-kindle"
      "slack"
      "spotify"
      "sublime-text"
      "temurin17"
      "bitwarden"
      "google-earth-pro"
      "calibre"
      "hiddenbar"
      "chatgpt"
      "obsidian"
      "itsycal"
      "mongodb-compass"
      "stremio"
    ];

    # `mas search <>` can help pinpoint package name
    masApps = {
      "Tailscale" = 1475387142; # Tailscale does have a brew package, however this is slightly more complete
      "Bandwidth+" = 490461369;
    };
  };
}
