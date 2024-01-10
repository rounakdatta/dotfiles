{ config, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  home.file.".config/gopass/config".text =
    if isDarwin then ''
      [mounts]
          path = ${config.home.homeDirectory}/.password-store
    ''
    else
      ''
        [mounts]
            path = ${config.home.homeDirectory}/.local/share/.password-store
      '';
}
