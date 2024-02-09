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
    caskArgs.no_quarantine = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };

    # taps to open, let packages rain
    taps = [
      "d12frosted/emacs-plus"
      "pulumi/tap"
      "homebrew/cask-versions"
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
      "joshjon-nocturnal"
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
    ];

    # `mas search <>` can help pinpoint package name
    masApps = {
      "Tailscale" = 1475387142; # Tailscale does have a brew package, however this is slightly more complete
    };
  };
}
