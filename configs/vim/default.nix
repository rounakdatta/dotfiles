{ config, pkgs, ... }: {
  programs.neovim = {
    enable = true;
    vimAlias = true;
    
    plugins = with pkgs.vimPlugins; [
      {
        plugin = pkgs.vimUtils.buildVimPlugin {
          name = "copilot.lua";
          src = pkgs.fetchFromGitHub {
            owner = "zbirenbaum";
            repo = "copilot.lua";
            rev = "master";
            sha256 = "sha256-Jw4Q76FolG3F/AN7WZn/mNNde/21uAJ+yqESmOlyNww=";
          };
        };
        config = ''
          lua << EOF
          require('copilot').setup({
            suggestion = {
              enabled = true,
              auto_trigger = true,
              debounce = 75,
              keymap = {
                accept = "<C-j>",
                accept_word = false,
                accept_line = false,
                next = "<M-]>",
                prev = "<M-[>",
                dismiss = "<C-]>",
              },
            },
            panel = {
              enabled = true,
              auto_refresh = false,
              keymap = {
                jump_prev = "[[",
                jump_next = "]]",
                accept = "<CR>",
                refresh = "gr",
                open = "<M-CR>"
              },
            },
            filetypes = {
              yaml = true,
              markdown = true,
              help = true,
              gitcommit = true,
              gitrebase = true,
              hgcommit = true,
              svn = true,
              cvs = true,
              ["."] = true,
            },
          })
          EOF
        '';
      }
    ];
    
    extraConfig = ''
      set clipboard=unnamedplus
      set autoindent

      set number

      let &t_SI = "\<esc>[5 q"
      let &t_SR = "\<esc>[5 q"
      let &t_EI = "\<esc>[2 q"

      set backspace=2

      set ignorecase
      set smartcase
    '';
  };
}
