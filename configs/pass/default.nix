{ config, lib, pkgs, ... }:
let
  passwordStoreDir = "${config.home.homeDirectory}/.password-store";
in
{
  programs.password-store.settings = lib.mkIf config.programs.password-store.enable {
    PASSWORD_STORE_DIR = passwordStoreDir;
  };

  home.activation = {
    # Activation entries are concatenated into a single `set -e` script, so this
    # step must never abort the run and must be safe to re-run: on a fresh
    # machine SSH access to gitlab is set up out-of-band, so the actual clone
    # only succeeds on a later switch. The whole body runs in a subshell so a
    # failed `cd` (or `exit`) is scoped here and the working-directory change
    # never leaks into later activation steps.
    passwordStore = ''
      (
        PW_DIR=${passwordStoreDir}

        mkdir -p "$PW_DIR"
        cd "$PW_DIR" || exit 0

        # make sure binaries like `git`, `ssh`, `gopass-jsonapi` are on PATH
        export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:$PATH"
        # `ssh` lives here on darwin, so there we go
        export PATH="/usr/bin:$PATH"

        git init
        if git remote | grep -q origin; then
            git remote set-url origin git@gitlab.com:rounakdatta/pass.git
        else
            git remote add origin git@gitlab.com:rounakdatta/pass.git
        fi

        # SSH access to gitlab may not be set up on the first switch; don't let a
        # failed fetch/pull abort activation. A later switch syncs the store once
        # access is in place.
        if ! (git fetch origin && git pull origin master); then
            echo "note: could not sync password-store from gitlab (SSH access set up yet?); skipping. It will sync on the next 'home-manager switch'." >&2
        fi

        # browser integration is best-effort; skip if gopass-jsonapi can't configure yet
        echo "Y" | gopass-jsonapi configure --browser chrome --global=false --path=${config.home.homeDirectory}/.config/gopass || true
        echo "Y" | gopass-jsonapi configure --browser firefox --global=false --path=${config.home.homeDirectory}/.config/gopass || true
      ) || true
    '';
  };
}
