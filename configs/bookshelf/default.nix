{ lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
# Darwin-only: books get downloaded on trueswiftie. On NixOS and festie this
  # module is a no-op.
lib.mkIf isDarwin {
  # `shelve` puts EPUBs on the bookshelf at books.taptappers.club (homelab.setup
  # kubernetes/apps/bookshelf), where the old iPad picks them up. With no
  # arguments it takes every EPUB in ~/Downloads, uploads it with the password
  # from pass books.taptappers.club, and moves it to ~/Books.
  #
  # The shelf used to run here, as a launchd agent serving ~/Books. It moved
  # to the homelab so the iPad can reach it wherever it is and whether or not
  # the laptop is awake; only the uploader is left on this side.
  home.packages = [
    (pkgs.writeShellScriptBin "shelve" ''
      exec ${pkgs.python3}/bin/python3 ${./shelve.py} "$@"
    '')
  ];
}
