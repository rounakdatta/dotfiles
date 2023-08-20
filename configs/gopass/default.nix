{ config, pkgs, ... }: {
    home.file.".config/gopass/config".text = ''
    [mounts]
        path = ${config.home.homeDirectory}/.password-store
    '';
}
