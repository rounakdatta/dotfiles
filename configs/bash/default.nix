{ config, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  programs.bash = {
    enable = true;
    initExtra = ''
      export LC_ALL=en_US.UTF-8
      export LANG=en_US.UTF-8
    '' +
    (if isDarwin then
      ''
        export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:$PATH"
        export PATH="$PATH:/etc/profiles/per-user/${config.home.username}/bin"
        export PATH="$PATH:/opt/homebrew/bin"
        export PATH="$PATH:/opt/homebrew/opt/node@18/bin"
        export JAVA_HOME=/usr/libexec/java_home
        # TODO: verify if this is at all needed at all needed
        export PASSWORD_STORE_DIR="/Users/${config.home.username}/.password-store"
      ''
    else
      ''
      ''
    );
  };
}
