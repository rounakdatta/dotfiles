{ config, pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
  user = import ../../lib/user.nix;
  # the exported, passphrase-protected secret key lives here on a fresh machine
  gpgKeyImportPath = "${config.home.homeDirectory}/.secrets/private.key";
in
{
  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    # mkDefault so a headless host can swap these out. Both defaults assume a
    # graphical session with a systemd user bus behind it, which is exactly
    # what a container does not have.
    pinentry.package = lib.mkDefault (if isDarwin then pkgs.pinentry_mac else pkgs.pinentry-gnome3);
    enableSshSupport = lib.mkDefault (!isDarwin);
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

  # Trust our own key. This is the other half of importGpgKey, and it is easy to
  # believe it is unnecessary: ownertrust is NOT part of a key. It lives in
  # trustdb.gpg, which is per-machine, and `gpg --import` never carries it --
  # moving it is a separate --export-ownertrust/--import-ownertrust pair.
  #
  # So every host bootstrapped by the import above ends up holding the secret key
  # while trusting it not at all. The failure is lopsided, which is why it hid for
  # so long: decryption needs no trust, so `pass show` and every pass-backed MCP
  # server worked fine, while *encryption* failed with "There is no assurance this
  # key belongs to the named user" / "Unusable public key". `pass insert` was
  # therefore impossible on festie from the day it was built, and nothing said so
  # until someone tried to write a secret rather than read one. (Confirmed: the
  # password store's history contains exactly one commit ever authored on festie.)
  #
  # ninezeroes and trueswiftie never showed it because the key was generated on a
  # laptop, and gpg gives ultimate ownertrust to keys it generates itself.
  #
  # Idempotent: a no-op once the record exists.
  home.activation.trustOwnGpgKey = lib.hm.dag.entryAfter [ "importGpgKey" ] ''
    GPG="${pkgs.gnupg}/bin/gpg"
    # --export-ownertrust keys its records by full 40-char fingerprint, while
    # lib/user.nix carries the 16-char long ID. Ask gpg to map one to the other
    # rather than keeping a second copy of the fingerprint in this repo.
    fpr="$("$GPG" --with-colons --fingerprint ${user.gpgKey} 2>/dev/null \
          | ${pkgs.gawk}/bin/awk -F: '$1 == "fpr" { print $10; exit }')"
    if [ -n "$fpr" ]; then
      if ! "$GPG" --export-ownertrust 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "^$fpr:"; then
        # 6 = ultimate, which is what "this key is mine" means, and exactly what a
        # locally generated key is assigned automatically.
        echo "$fpr:6:" | "$GPG" --import-ownertrust 2>/dev/null || true
        echo "gnupg: marked own key $fpr ultimately trusted (encryption, e.g. pass insert, needs this)"
      fi
    fi
  '';
}
