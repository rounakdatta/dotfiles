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
    };
  };
}
