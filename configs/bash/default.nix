{ config, pkgs, ... }: {
  programs.bash = {
    enable = true;
    initExtra = ''
      export LC_ALL=en_US.UTF-8
      export LANG=en_US.UTF-8
    '';
  };
}
