{ config, pkgs, ... }: {
    programs.gpg = {
        enable = true;
    };

    services.nextcloud-client = {
        enable = true;
        startInBackground = true;
    };
}
