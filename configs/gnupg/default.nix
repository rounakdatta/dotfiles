{ config, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  # On macOS, use GPG Suite (Homebrew cask) for native keychain integration
  # On Linux, use Nix's GPG
  programs.gpg = {
    enable = !isDarwin;
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

