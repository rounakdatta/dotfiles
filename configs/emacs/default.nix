{ config, pkgs, ... }: {
  programs.emacs = {
    enable = true;
  };

  home.file.".doom.d/init.el".text = builtins.readFile ./init.el;
  home.file.".doom.d/config.el".text = builtins.readFile ./config.el;
  home.file.".doom.d/packages.el".text = builtins.readFile ./packages.el;

  # Doom Emacs setup is now idempotent and non-interactive for stable rebuilds
  # https://github.com/doomemacs/doomemacs/issues/5918#issuecomment-1028588770
  home.activation = {
    doomEmacs = ''
      DOOM="$HOME/.emacs.d"
      DOOM_INSTALLED_MARKER="$DOOM/.nix-doom-installed"

      # Only run full setup if Doom is not already installed
      if [ ! -f "$DOOM_INSTALLED_MARKER" ]; then
        echo "Installing Doom Emacs for the first time..."

        if [ ! -d "$DOOM" ]; then
            mkdir -p "$DOOM"
        fi
        cd $DOOM

        # the following PATH addition is to make sure that binaries like `git`, `emacs` are available for use
        export PATH="${config.home.path}/bin:$PATH"

        git init
        if git remote | grep -q origin; then
            git remote set-url origin https://github.com/doomemacs/doomemacs.git
        else
            git remote add origin https://github.com/doomemacs/doomemacs.git
        fi

        git fetch origin
        git pull origin master

        # the bash-subcommanding is done to avoid https://github.com/doomemacs/doomemacs/issues/4181#issuecomment-729741088
        bash -c "yes | $DOOM/bin/doom install"

        # Mark as installed to avoid re-running on every rebuild
        touch "$DOOM_INSTALLED_MARKER"
        echo "Doom Emacs installation complete. Run 'doom sync' manually if needed."
      else
        echo "Doom Emacs already installed. Skipping setup."
        echo "To sync packages, run: ~/.emacs.d/bin/doom sync"
      fi
    '';
  };
}
