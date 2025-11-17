{ config, pkgs, lib, user, ... }:

let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.programs.git;

  # a helper function to make it easy to define git aliases
  mkAlias = name: value:
    let
      # fail on list of strings
      # TODO: extend to support list of strings and concatenation
      # and probably move to a separate file, someday
      value' = if builtins.isString value then value else builtins.throw "alias value needs to be a string";
    in
    {
      name = name;
      value = value';
    };
in
{
  options.programs.git = {
    enable = mkEnableOption "git";
  };

  config = mkIf cfg.enable {
    programs.git = {
      enable = true;
      userEmail = user.email;
      userName = user.name;
      signing = {
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
              name = user.name;
              email = "rounak@lyric.tech";
              signingKey = user.gpgKey;
            };
          };
        }
        { path = "~/.gitconfig.https"; }
      ];
      extraConfig = {
        diff.external = "difft";
        "credential \"https://github.com\"".helper = "!/usr/bin/env GITHUB_TOKEN=$(gopass show github.com/pat) git-credential-helper store --file=/tmp/git-credential-github";
      };
    };

    home.activation = {
      # TODO: Beware! As long as this activation is there, changes made above will not take effect
      # you gotta comment the following section out to make changes above take effect
      # createTokenIncludedGitHubHttpsConfig = ''
      #   export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:$PATH"
      #   export PATH="/usr/bin:$PATH"
      #   GITCONFIG_HTTPS_FILE=${config.home.homeDirectory}/.gitconfig.https
      #   GH_PAT=$(gopass show github.com/pat)
      #   cat > "$GITCONFIG_HTTPS_FILE" <<EOF
      #   [url "https://rounakdatta:$GH_PAT@github.com/"]
      #     insteadOf = https://github.com/
      #   EOF
      # '';
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
