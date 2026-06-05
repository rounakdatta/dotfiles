{ config, pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    pinentry.package = if isDarwin then pkgs.pinentry_mac else pkgs.pinentry-gnome3;
    enableSshSupport = !isDarwin;
  };

  # GPG Suite (brew) ships gpg-agent 2.2.41 and auto-starts it, while nix's gpg
  # is 2.4.9. Both share ~/.gnupg/S.gpg-agent, so gopass/git hit the older agent
  # and decryption fails with "server gpg-agent is older than us" + "No secret
  # key". Reclaim the socket for nix's matching agent (key material in ~/.gnupg
  # is untouched). Uses nix's gpgconf explicitly so the relaunched agent is 2.4.9.
  home.activation.useNixGpgAgent = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      "${pkgs.gnupg}/bin/gpgconf" --kill gpg-agent || true
      "${pkgs.gnupg}/bin/gpgconf" --launch gpg-agent || true
    ''
  );
}
