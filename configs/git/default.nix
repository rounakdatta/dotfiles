{ config, pkgs, ... }: {
  programs.git = {
    enable = true;
    userEmail = "rounakdatta12@gmail.com";
    userName = "Rounak Datta";
    signing = {
      key = "A04E86FD28F5A421";
      signByDefault = true;
    };
    # the goal here is to have the correct ordering, the `[user]` block should come first, and then the `[include]` block
    # was able to fix the ordering using https://www.reddit.com/r/NixOS/comments/jg4i92/comment/j08vf4n
    includes = [
      { path = "~/.gitconfig.work"; }
      { path = "~/.gitconfig.https"; }
    ];
    extraConfig = {
      diff.external = "difft";
    };
  };

  home.activation = {
    createTokenIncludedGitHubHttpsConfig = ''
      export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:$PATH"
      export PATH="/usr/bin:$PATH"

      GITCONFIG_HTTPS_FILE=${config.home.homeDirectory}/.gitconfig.https
      GH_PAT=$(gopass show github.com/pat)

      cat > "$GITCONFIG_HTTPS_FILE" <<EOF
      [url "https://rounakdatta:$GH_PAT@github.com/"]
        insteadOf = https://github.com/
      EOF
    '';
  };

  home.file.".gitconfig.work".text = builtins.readFile ./gitconfig.work;
}

# note how the same key is used across both personal and work accounts
# to know the key ID
# gpg --list-secret-keys --keyid-format LONG
# gpg --edit-key <>
# adduid
# blah-blah-blah
# save
