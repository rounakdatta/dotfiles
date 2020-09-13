# Defined in /Users/dattar/.config/fish/functions/fish_prompt.fish @ line 1
function fish_prompt
    set_color $fish_color_cwd
    echo -n (basename $PWD)
    set_color normal
    set -g _fish_git_prompt_showupstream auto
    echo -n (fish_git_prompt) ' $ '
end
