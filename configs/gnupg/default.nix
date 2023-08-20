{ config, pkgs, ... }: {
    programs.gpg = {
        enable = true;
    };

    services.gpg-agent = {
        enable = true;
        pinentryFlavor = "gnome3";
        enableSshSupport = true;
    };
}
