{ config, lib, pkgs, ... }:
let
  passwordStoreDir = "${config.home.homeDirectory}/.password-store";
in
{
  programs.password-store.settings = lib.mkIf config.programs.password-store.enable {
    PASSWORD_STORE_DIR = passwordStoreDir;
  };

  home.activation = {
    # best-effort and re-runnable: gitlab SSH access is set up out-of-band, so
    # the clone only succeeds on a later switch. the subshell + `|| true` keeps
    # any failure (and the `cd`) from aborting or leaking into the rest of activation
    passwordStore = ''
      (
        PW_DIR=${passwordStoreDir}

        mkdir -p "$PW_DIR"
        cd "$PW_DIR" || exit 0

        # `git`/`ssh`/`gopass-jsonapi` on PATH; `ssh` lives under /usr/bin on darwin
        export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:$PATH"
        export PATH="/usr/bin:$PATH"

        git init
        if git remote | grep -q origin; then
            git remote set-url origin git@gitlab.com:rounakdatta/pass.git
        else
            git remote add origin git@gitlab.com:rounakdatta/pass.git
        fi

        git fetch origin && git pull origin master

        echo "Y" | gopass-jsonapi configure --browser chrome --global=false --path=${config.home.homeDirectory}/.config/gopass
        echo "Y" | gopass-jsonapi configure --browser firefox --global=false --path=${config.home.homeDirectory}/.config/gopass
      ) || true
    '';
  };
}
