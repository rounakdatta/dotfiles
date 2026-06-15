{ config, lib, ... }:

let
  cfg = config.programs.cargo-packages;
in
{
  options.programs.cargo-packages = {
    enable = lib.mkOption { type = lib.types.bool; default = true; };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Crates to install via 'cargo install'. Each entry is passed verbatim
        as the arguments to 'cargo install', so both registry crates
        ("ripgrep", "cargo-edit --version 0.12") and git sources
        ("--git https://github.com/owner/repo") are supported.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.packages != [ ]) {
    home.sessionPath = [ "${config.home.homeDirectory}/.cargo/bin" ];

    home.activation.cargoInstall = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # /usr/bin is needed so `cargo install` finds the system `cc` (Xcode CLT)
      # to link binaries; the activation PATH doesn't include it by default.
      export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:/opt/homebrew/bin:$HOME/.cargo/bin:/usr/bin:$PATH"

      if ! command -v cargo >/dev/null 2>&1; then
        echo "Skipping cargo package install because cargo is unavailable"
        exit 0
      fi

      ${lib.concatMapStringsSep "\n" (pkg: ''
        echo "Installing ${pkg}..."
        cargo install ${pkg} || true
      '') cfg.packages}
    '';
  };
}
