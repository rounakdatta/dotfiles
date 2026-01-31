{ config, lib, ... }:

let
  cfg = config.programs.go-packages;
in
{
  options.programs.go-packages = {
    enable = lib.mkOption { type = lib.types.bool; default = true; };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Go packages to install via 'go install'";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.packages != [ ]) {
    home.activation.goInstall = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      export PATH="/opt/homebrew/bin:$HOME/go/bin:$PATH"
      export GOPATH="$HOME/go"

      ${lib.concatMapStringsSep "\n" (pkg: ''
        echo "Installing ${pkg}..."
        go install ${pkg} || true
      '') cfg.packages}
    '';
  };
}
