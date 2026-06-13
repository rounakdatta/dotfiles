{ config, lib, pkgs, ... }:
let
  atuinDir = "${config.home.homeDirectory}/.local/share/atuin";
  atuinUser = "rounakdatta";
  keyEntry = "Account/atuin.sh/key";
  pwEntry = "Account/atuin.sh/rounakdatta";
in
{
  # On a fresh machine, restore atuin's end-to-end encryption key from pass and
  # log in, so sync works out of the box. atuin otherwise generates a *new* key
  # that can't decrypt the server's already-synced history, silently
  # half-breaking sync (hit 2026-06: sync aborts on the first undecryptable
  # record). Runs only when the key is missing — it never clobbers a working
  # key — and is best-effort if gpg/pass/network aren't ready yet.
  home.activation.restoreAtuin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    keyFile="${atuinDir}/key"
    if [ ! -s "$keyFile" ]; then
      export PATH="${config.home.path}/bin:/run/current-system/sw/bin:$PATH"
      pass="${pkgs.pass}/bin/pass"
      mkdir -p "${atuinDir}"
      if "$pass" show "${keyEntry}" > "$keyFile.tmp" 2>/dev/null && [ -s "$keyFile.tmp" ]; then
        mv "$keyFile.tmp" "$keyFile" && chmod 600 "$keyFile"
        echo "atuin: restored encryption key from pass (${keyEntry})"
        if ${pkgs.atuin}/bin/atuin login -u "${atuinUser}" -p "$("$pass" show "${pwEntry}")" >/dev/null 2>&1; then
          echo "atuin: logged in as ${atuinUser}"
        else
          echo "atuin: key restored; run 'atuin login -u ${atuinUser}' to finish sync setup"
        fi
      else
        rm -f "$keyFile.tmp"
        echo "atuin: no local key and pass unavailable — run: pass show ${keyEntry} > $keyFile && chmod 600 $keyFile"
      fi
    fi
  '';
}
