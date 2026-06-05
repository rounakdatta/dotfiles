{ config, lib, pkgs, ... }:
let
  passwordStoreDir = "${config.home.homeDirectory}/.password-store";
in
{
  programs.password-store.settings = lib.mkIf config.programs.password-store.enable {
    PASSWORD_STORE_DIR = passwordStoreDir;
  };

  home.activation = {
    passwordStore = ''
      PW_DIR=${passwordStoreDir}

      if [ ! -d "$PW_DIR" ]; then
          mkdir -p "$PW_DIR"
      fi
      cd $PW_DIR

      # the following PATH addition is to make sure that binaries like `git`, `emacs`, `ssh` are available for use
      export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:$PATH"
      # `ssh` is on the following path in darwin, so there we go
      export PATH="/usr/bin:$PATH"

      git init
      if git remote | grep -q origin; then
          git remote set-url origin git@gitlab.com:rounakdatta/pass.git
      else
          git remote add origin git@gitlab.com:rounakdatta/pass.git
      fi

      # On a fresh machine SSH keys to gitlab may not be set up yet; don't let a
      # failed fetch/pull abort the whole home-manager activation. A later switch
      # will sync the store once SSH access is in place.
      if ! (git fetch origin && git pull origin master); then
          echo "warning: could not sync password-store from gitlab (SSH keys set up yet?); skipping. Re-run 'home-manager switch' once access is configured." >&2
      fi

      # browser integration is best-effort; skip silently if gopass-jsonapi can't configure yet
      echo "Y" | gopass-jsonapi configure --browser chrome --global=false --path=${config.home.homeDirectory}/.config/gopass || true
      echo "Y" | gopass-jsonapi configure --browser firefox --global=false --path=${config.home.homeDirectory}/.config/gopass || true
    '';
  };
}
