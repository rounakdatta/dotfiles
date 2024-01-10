{ config, pkgs, ... }: 
let
    isDarwin = pkgs.stdenv.isDarwin;
in {
        programs.fish = {
            enable = true;
            interactiveShellInit = ''
            if [ -n "$TMUX_PANE" ]
              set HISTFILE $HOME/.local/share/fish/fish_history_tmux_$TMUX_PANE
            end

            set GOPATH $HOME/go
            set PATH $GOPATH/bin $PATH
            set EDITOR nvim
            set SHELL /run/current-system/sw/bin/fish
            
            # although we've set the NixOS-level setting, remember that Chrome would require this `TZ` envvar
            # otherwise, it defaults to UTC
            set TZ Asia/Kolkata
            '' +
            ''
            set -gx LC_ALL en_IN.UTF-8
            set -gx LANG en_IN.UTF-8

            set -U fish_color_autosuggestion      brblack
            set -U fish_color_cancel              -r
            set -U fish_color_command             brgreen
            set -U fish_color_comment             brmagenta
            set -U fish_color_cwd                 green
            set -U fish_color_cwd_root            red
            set -U fish_color_end                 brmagenta
            set -U fish_color_error               brred
            set -U fish_color_escape              brcyan
            set -U fish_color_history_current     --bold
            set -U fish_color_host                normal
            set -U fish_color_match               --background=brblue
            set -U fish_color_normal              normal
            set -U fish_color_operator            cyan
            set -U fish_color_param               brblue
            set -U fish_color_quote               yellow
            set -U fish_color_redirection         bryellow
            set -U fish_color_search_match        'bryellow' '--background=brblack'
            set -U fish_color_selection           'white' '--bold' '--background=brblack'
            set -U fish_color_status              red
            set -U fish_color_user                brgreen
            set -U fish_color_valid_path          --underline
            set -U fish_greeting                  
            set -U fish_pager_color_completion    normal
            set -U fish_pager_color_description   yellow
            set -U fish_pager_color_prefix        'white' '--bold' '--underline'
            set -U fish_pager_color_progress      'brwhite' '--background=cyan'
            '' +
            ''
            alias pbcopy="xsel --clipboard --input"
            alias pbpaste="xsel --clipboard --output"
	          alias vim="nvim"
            '' +
            (if isDarwin then
            ''
            # this is needed, otherwise darwin-rebuild wouldn't be in PATH
            fish_add_path --prepend --global "$HOME/.nix-profile/bin" /nix/var/nix/profiles/default/bin /run/current-system/sw/bin
            set PATH $PATH /etc/profiles/per-user/${config.home.username}/bin
            set PATH $PATH /opt/homebrew/bin
            ''
            else
            ''
            ''
            )
            +
            ''
            atuin init fish --disable-up-arrow | source
            ''
            ;
            functions = {
                fish_prompt = ''
		            # special treatment just for nix-develop shells
		            if set -q IN_NIX_DEVELOP_SHELL
		              echo -n "[NIX-DEVELOP] "
		            end

                set_color $fish_color_cwd
                echo -n (basename $PWD)
                set_color normal
                set -g _fish_git_prompt_showupstream auto
                echo -n (fish_git_prompt) ' $ '
                '';
            };
    };
}
