{ config, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  programs.gpg = {
    enable = true;
  };

  services.gpg-agent =
    if isDarwin then {
      enable = false;
    } else {
      enable = true;
      pinentryPackage = pkgs.pinentry-gnome3;
      enableSshSupport = true;
    };
}

