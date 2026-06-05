{ config, lib, pkgs, ... }:
let
  passwordStoreDir = "${config.home.homeDirectory}/.password-store";
in
{
  programs.password-store.settings = lib.mkIf config.programs.password-store.enable {
    PASSWORD_STORE_DIR = passwordStoreDir;
  };

  home.activation = {
    # best-effort, re-runnable store bootstrap. gitlab access is set up
    # out-of-band, so the sync only succeeds on a later switch; the subshell
    # (+ `|| true`) keeps any failure and the `cd` from leaking into the rest
    # of activation.
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

        # BatchMode/accept-new so activation can't stall on an SSH host-key or
        # passphrase prompt; point at the manual command rather than guessing why
        export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
        if ! { git fetch origin && git pull origin master; } >/dev/null 2>&1; then
            echo "note: password-store not synced; run 'git -C $PW_DIR pull' once gitlab access is set up"
        fi

        # browser integration needs an initialized store
        if [ -f "$PW_DIR/.gpg-id" ]; then
            echo "Y" | gopass-jsonapi configure --browser chrome --global=false --path=${config.home.homeDirectory}/.config/gopass
            echo "Y" | gopass-jsonapi configure --browser firefox --global=false --path=${config.home.homeDirectory}/.config/gopass
        fi
      ) || true
    '';
  };
}
