{ config, lib, pkgs, ... }:
let
  user = import ../../lib/user.nix;
  passwordStoreDir = "${config.home.homeDirectory}/.password-store";
in
{
  programs.git = {
    enable = true;
    signing = {
      format = "openpgp";
      key = user.gpgKey;
      signByDefault = true;
    };
    # the goal here is to have the correct ordering, the `[user]` block should come first, and then the `[include]` block
    # was able to fix the ordering using https://www.reddit.com/r/NixOS/comments/jg4i92/comment/j08vf4n
    includes = [
      {
        condition = "gitdir:~/work/";
        contents = {
          user = {
            name = "Rounak Datta";
            email = "rounak@lyric.tech";
            signingKey = "A04E86FD28F5A421";
          };
        };
      }
      { path = "~/.gitconfig.https"; }
    ];
    settings = {
      user = {
        email = user.email;
        name = "Rounak Datta";
      };
      diff.external = "difft";
    };
  };

  # TODO: Beware! As long as this activation is there, changes made above will not take effect
  # you gotta comment the following section out to make changes above take effect
  home.activation = {
    createTokenIncludedGitHubHttpsConfig = lib.hm.dag.entryAfter [ "passwordStore" ] ''
      export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:$PATH"
      export PATH="/usr/bin:$PATH"

      GITCONFIG_HTTPS_FILE=${config.home.homeDirectory}/.gitconfig.https

      # the store is set up out-of-band, so this no-ops until `.gpg-id` exists;
      # gating on it avoids gopass' "not initialized" error and a pinentry hang
      if [ -f "${passwordStoreDir}/.gpg-id" ] && GH_PAT=$(gopass show github.com/pat 2>/dev/null) && [ -n "$GH_PAT" ]; then
        {
          echo "[url \"https://rounakdatta:$GH_PAT@github.com/\"]"
          echo "  insteadOf = https://github.com/"
        } > "$GITCONFIG_HTTPS_FILE"
      fi
    '';
  };
}

# note how the same key is used across both personal and work accounts
# to know the key ID
# gpg --list-secret-keys --keyid-format LONG
# gpg --edit-key <>
# adduid
# blah-blah-blah
# save
