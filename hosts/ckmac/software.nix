{ pkgs, ... }: {

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
    ];

    # `brew list <>` can help pinpoint package name
    # for both ordinary packages and casks
    brews = [
        "curl"
        "nextcloud"
        "awscli"
        "d12frosted/emacs-plus/emacs-plus"
        "mas"
        "pinentry-mac"
        "pulumi/tap/pulumi"
        "skaffold"
        "watch"
        "yarn" # the JS package manager, not the hadoop scheduler
    ];

    casks = [
        "google-chrome"
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
        "temurin17" # presently the best FOSS Java SDK
    ];

    # `mas search <>` can help pinpoint package name
    masApps = {
        "Tailscale" = 1475387142; # Tailscale does have a brew package, however this is slightly more complete
    };
  };
}
