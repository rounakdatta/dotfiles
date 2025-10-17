{ inputs, pkgs, self, ... }: {
  imports = [
    ./git
    ./tmux
    ./vim
    ./bash
    ./fish
    ./gnupg
    ./ssh
    ./pass
    ./gopass
    ./nextcloud
    ./emacs
    ./claude
  ];
}
