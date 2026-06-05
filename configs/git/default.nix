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
  # run after `passwordStore` so the store has been cloned before we read from it
  home.activation = {
    createTokenIncludedGitHubHttpsConfig = lib.hm.dag.entryAfter [ "passwordStore" ] ''
      export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:$PATH"
      export PATH="/usr/bin:$PATH"

      GITCONFIG_HTTPS_FILE=${config.home.homeDirectory}/.gitconfig.https

      # The password store is set up out-of-band (GPG key imported, gitlab repo
      # cloned) and may not exist on the first switch of a fresh machine - it
      # only lands on a later switch. So this step must be a no-op until the
      # store is genuinely usable, and must never abort the activation.
      #
      # Gate on `.gpg-id` (gopass' marker for an initialized store) before
      # touching gopass at all: this is deterministic, avoids the "password-store
      # is not initialized" error, and sidesteps a pinentry hang on a
      # half-configured store. Once the store is ready a later switch fills the
      # file in. A missing include file is ignored by git, so skipping is safe.
      if [ -f "${passwordStoreDir}/.gpg-id" ] && GH_PAT=$(gopass show github.com/pat 2>/dev/null) && [ -n "$GH_PAT" ]; then
        {
          echo "[url \"https://rounakdatta:$GH_PAT@github.com/\"]"
          echo "  insteadOf = https://github.com/"
        } > "$GITCONFIG_HTTPS_FILE"
      else
        echo "note: password store not ready (github.com/pat unavailable); skipping $GITCONFIG_HTTPS_FILE. It will be generated on the next 'home-manager switch' after the store is set up." >&2
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
