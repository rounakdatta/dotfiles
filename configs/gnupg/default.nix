{ config, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    pinentryPackage = if isDarwin then pkgs.pinentry_mac else pkgs.pinentry-gnome3;
    enableSshSupport = !isDarwin;
  };
}
