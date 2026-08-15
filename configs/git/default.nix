{ config, lib, pkgs, ... }:
let
  user = import ../../lib/user.nix;
  passwordStoreDir = "${config.home.homeDirectory}/.password-store";
  cfg = config.programs.githubOverSsh;
in
{
  options.programs.githubOverSsh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Rewrite GitHub HTTPS remotes to SSH, and stop writing the PAT-bearing
        ~/.gitconfig.https.

        For hosts where the PAT path is not deterministic. It depends on
        gopass, which depends on the GPG key being unlocked *at activation
        time* — and on a freshly booted festie nobody has unlocked it yet, so
        the file is silently never written and every push fails with
        "could not read Username for 'https://github.com'". Whether git works
        then depends on whether a human happened to decrypt something first.

        The mounted SSH key has no passphrase and is already what configs/ssh
        points github.com at, so routing git over it removes the ordering
        dependency entirely. Commit *signing* still needs the key unlocked;
        that is a separate concern from transport.
      '';
    };
  };

  # Everything below sits under an explicit `config`, which the options block
  # above makes mandatory: a module that declares top-level `options` may not
  # also carry bare configuration attributes.
  config = {
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
      } // lib.optionalAttrs cfg.enable {
        # Deliberately the only insteadOf rule on such a host: the PAT include
        # declares the same rewrite, and two live rules for one prefix make
        # which credential git picks a coin flip.
        url."git@github.com:".insteadOf = "https://github.com/";
      };
    };

    # TODO: Beware! As long as this activation is there, changes made above will not take effect
    # you gotta comment the following section out to make changes above take effect
    home.activation = {
      createTokenIncludedGitHubHttpsConfig = lib.hm.dag.entryAfter [ "passwordStore" ] (
        if cfg.enable then ''
          # This host routes GitHub over SSH, so the PAT include must not merely
          # go unwritten — it must be actively removed. A copy left behind by an
          # earlier generation (or by an activation that ran while the key
          # happened to be unlocked) is still on disk and still included, and it
          # would race the SSH rewrite for the same prefix.
          rm -f "${config.home.homeDirectory}/.gitconfig.https"
        '' else ''
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
        ''
      );
    };
  };
}

# note how the same key is used across both personal and work accounts
# to know the key ID
# gpg --list-secret-keys --keyid-format LONG
# gpg --edit-key <>
# adduid
# blah-blah-blah
# save
