{ config, lib, ... }:
let
  cfg = config.programs.npm-packages;
  npmPrefix = "${config.home.homeDirectory}/.npm-packages";
in
{
  options.programs.npm-packages = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "npm packages to install in a user-local prefix";
    };
  };

  config = lib.mkIf cfg.enable {
    home.sessionPath = [
      "${npmPrefix}/bin"
    ];

    home.sessionVariables = {
      NPM_CONFIG_PREFIX = npmPrefix;
    };

    home.activation.npmPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:/opt/homebrew/bin:/opt/homebrew/opt/node@18/bin:/usr/bin:$PATH"
      export NPM_CONFIG_PREFIX="${npmPrefix}"
      export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

      mkdir -p "$NPM_CONFIG_PREFIX"

      # if/else rather than an early `exit`: home-manager concatenates every
      # home.activation block into ONE bash script, so `exit` here would end the
      # whole activation run — every step ordered after this one silently never
      # runs. See configs/mic for the outage this actually caused.
      if ! command -v npm >/dev/null 2>&1; then
        echo "Skipping npm package install because npm is unavailable"
      else
        # Keeps the branch non-empty when no packages are configured: `packages`
        # defaults to [ ], and bash rejects an `else` with nothing in it.
        :
        ${lib.concatMapStringsSep "\n" (pkg: ''
          echo "Installing npm package ${pkg}..."
          npm install --global --location=global ${pkg}
        '') cfg.packages}
      fi
    '';
  };
}
