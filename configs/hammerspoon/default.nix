{ config, lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;

  # The desk-pet overlay. Hammerspoon (the app) is installed as a brew cask in
  # hosts/trueswiftie/software.nix; here we just manage its config. @TMUX@ is
  # replaced with the absolute tmux path (so click-to-jump and focus-aware
  # queries don't depend on Hammerspoon's PATH), and @LOGO@ with the store path
  # of the embedded Claude logo PNG.
  petLua = builtins.replaceStrings
    [ "@TMUX@" "@LOGO@" ]
    [ "${pkgs.tmux}/bin/tmux" "${./claudecode-color.png}" ]
    (builtins.readFile ./claude-pet.lua);
in
# Darwin-only: Hammerspoon is a macOS app. On NixOS this module is a no-op.
lib.mkIf isDarwin {
  home.file.".hammerspoon/init.lua".text = petLua;
}
