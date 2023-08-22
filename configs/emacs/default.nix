{ config, pkgs, ... }: {
    programs.emacs = {
        enable = true;
    };

    home.file.".doom.d/init.el".text = builtins.readFile ./init.el;
    home.file.".doom.d/config.el".text = builtins.readFile ./config.el;
    home.file.".doom.d/packages.el".text = builtins.readFile ./packages.el;

    home.activation = {
        doomEmacs = ''
            DOOM="$HOME/.emacs.d"

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
            # unfortunately this step takes a lot of time, and Nix reports it as a timeout
            # as of now, this step has to be run manually externally in the very first-time setup
            # successive runs however should be fine
            $DOOM/bin/doom sync
        '';
    };
}
