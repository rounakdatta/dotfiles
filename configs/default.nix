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
    ./codeman
    ./festie-doctor
    ./go
    ./cargo
    ./mic
    ./claude-skills
    ./veans
    ./atuin
    ./hammerspoon
    ./screensaver
  ];
}
