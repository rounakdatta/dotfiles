{ config, pkgs, ... }: {
  programs.git = {
    enable = true;
    userEmail = "rounakdatta12@gmail.com";
    userName = "Rounak Datta";
    signing = {
      key = "A04E86FD28F5A421";
      signByDefault = true;
    };
    extraConfig = {
      diff.external = "difft";
      "includeIf \"gitdir:~/work/\"" = {
        path = "~/.gitconfig.work";
      };
    };
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
