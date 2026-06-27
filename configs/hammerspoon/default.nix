{ config, lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;

  # The desk-pet overlay. Hammerspoon (the app) is installed as a brew cask in
  # hosts/trueswiftie/software.nix; here we just manage its config. @TMUX@ is
  # replaced with the absolute tmux path (so click-to-jump and focus-aware
  # queries don't depend on Hammerspoon's PATH); @LOGO@ with the orange Claude
  # logo (sessions needing you), and @LOGO_WORKING@ with the grey logo
  # (sessions currently working — grey so it stays visible on a dark terminal).
  petLua = builtins.replaceStrings
    [ "@TMUX@" "@LOGO@" "@LOGO_WORKING@" ]
    [ "${pkgs.tmux}/bin/tmux" "${./claudecode-color.png}" "${./claudecode-gray.png}" ]
    (builtins.readFile ./claude-pet.lua);
in
# Darwin-only: Hammerspoon is a macOS app. On NixOS this module is a no-op.
lib.mkIf isDarwin {
  home.file.".hammerspoon/init.lua".text = petLua;
}
