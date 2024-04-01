{ config, pkgs, ... }: {

  home.file.".scripts/automata/snibox2memoet.js".text = builtins.readFile ./snibox2memoet.js;
  home.file.".scripts/automata/snibox2memoet.sh".text = builtins.readFile ./snibox2memoet.sh;

  home.activation = {
    puppeteerSetup = ''
      export PATH="${config.home.path}/bin:$PATH"
      export PATH="$PATH:/opt/homebrew/opt/node@18/bin"
      echo $PATH
      which npm
      npm install -g puppeteer-core
    '';
  };
}
