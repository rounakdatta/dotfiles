{ config, pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
  user = import ../../lib/user.nix;
  # drop the exported, passphrase-protected secret key here on a fresh machine
  gpgKeyImportPath = "${config.home.homeDirectory}/.gnupg/${user.gpgKey}.asc";
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

  # gopass/git decryption needs the private key, but on a fresh machine
  # `gpg --list-secret-keys` is empty. Import it once from a known path: drop the
  # armored key at gpgKeyImportPath and switch. Idempotent (skips if already in
  # the keyring); `--batch --import` is non-interactive and needs no passphrase.
  home.activation.importGpgKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    GPG="${pkgs.gnupg}/bin/gpg"
    if ! "$GPG" --list-secret-keys ${user.gpgKey} >/dev/null 2>&1; then
      if [ -f "${gpgKeyImportPath}" ]; then
        "$GPG" --batch --import "${gpgKeyImportPath}" || true
      else
        echo "note: GPG secret key ${user.gpgKey} not in keyring; drop the armored key at ${gpgKeyImportPath} and re-run 'home-manager switch'"
      fi
    fi
  '';
}
