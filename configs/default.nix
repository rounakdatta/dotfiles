{ inputs, pkgs, self, ... }: {
  imports = [
    ./git
    ./tmux
    ./vim
    ./bash
    ./fish
    ./gnupg
    ./ssh
    ./gopass
    ./nextcloud
    ./emacs
  ];
}
