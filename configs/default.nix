{ inputs, pkgs, self, ... }: {
  imports = [
    ./git
    ./tmux
    ./vim
    ./fish
    ./gnupg
    ./ssh
    ./gopass
    ./nextcloud
  ];
}
