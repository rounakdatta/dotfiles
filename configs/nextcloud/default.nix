{ config, pkgs, ... }: 
let
    isDarwin = pkgs.stdenv.isDarwin;
in {
    services.nextcloud-client = if isDarwin then {
        enable = false;
    } else {
        enable = true;
        startInBackground = true;
    };
}
