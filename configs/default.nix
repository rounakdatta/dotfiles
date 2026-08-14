{ inputs, pkgs, self, ... }: {
  imports = [
    ./git
    ./tmux
    ./vim
    ./bash
    ./fish
    ./npm
    ./gnupg
    ./ssh
    ./pass
    ./gopass
    ./nextcloud
    ./emacs
    ./claude
    ./go
    ./cargo
    ./mic
    ./claude-skills
    ./atuin
    ./hammerspoon
    ./screensaver
  ];
}
