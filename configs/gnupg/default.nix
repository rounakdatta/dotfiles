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

  # Configure GPG settings via home.file for consistency across both platforms
  home.file.".gnupg/gpg.conf".text = ''
    # Use GPG Suite's pinentry on macOS
    ${if isDarwin then "# Using GPG Suite from Homebrew" else ""}
  '';
}

