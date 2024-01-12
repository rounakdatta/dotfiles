{ config, pkgs, ... }: {
  programs.neovim = {
    enable = true;
    vimAlias = true;
    extraConfig = ''
      set clipboard=unnamedplus
      set autoindent

      set number

      let &t_SI = "\<esc>[5 q"
      let &t_SR = "\<esc>[5 q"
      let &t_EI = "\<esc>[2 q"

      set backspace=2
      set smartcase
    '';
  };
}
