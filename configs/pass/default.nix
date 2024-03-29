{ config, pkgs, ... }: {
  home.activation = {
    passwordStore = ''
      PW_DIR=${config.home.homeDirectory}/.password-store

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

      git fetch origin
      git pull origin master

      echo "Y" | gopass-jsonapi configure --browser chrome --global=false --path=${config.home.homeDirectory}/.config/gopass
      echo "Y" | gopass-jsonapi configure --browser firefox --global=false --path=${config.home.homeDirectory}/.config/gopass
    '';
  };
}
