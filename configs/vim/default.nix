{ config, pkgs, ... }: {
  programs.neovim = {
    enable = true;
    vimAlias = true;
    
    plugins = with pkgs.vimPlugins; [
      plenary-nvim
      {
        plugin = pkgs.vimUtils.buildVimPlugin {
          name = "claude-code.nvim";
          src = pkgs.fetchFromGitHub {
            owner = "greggh";
            repo = "claude-code.nvim";
            rev = "main";
            sha256 = "sha256-0crfj852lwif5gipckb3hzagrvjccl6jg7xghs02d0v1vjx0yhk4";
          };
        };
        type = "lua";
        config = ''
          require("claude-code").setup({
            -- Optional: Configure window settings
            window = {
              relative = "editor",
              width = 0.8,
              height = 0.8,
              border = "rounded",
            },
          })
          
          -- Key mappings
          vim.keymap.set('n', '<C-,>', ':ClaudeCode<CR>', { noremap = true, silent = true })
          vim.keymap.set('n', '<leader>cC', ':ClaudeCodeContinue<CR>', { noremap = true, silent = true })
          vim.keymap.set('n', '<leader>cV', ':ClaudeCodeVerbose<CR>', { noremap = true, silent = true })
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
