{ config, pkgs, ... }: {
  programs.ssh = {
    enable = true;
    # Explicitly disable default config to silence deprecation warning
    enableDefaultConfig = false;

    matchBlocks = {
      # Default config for all hosts
      "*" = {
        # Add any default SSH settings you want here
      };

      "github.com" = {
        user = "rounakdatta";
        identityFile = "~/.ssh/keys/personal.pem";
        extraOptions = {
          PreferredAuthentications = "publickey";
        };
      };

      "gitlab.com" = {
        user = "rounakdatta";
        identityFile = "~/.ssh/keys/personal.pem";
        extraOptions = {
          PreferredAuthentications = "publickey";
        };
      };

      "jomjom" = {
        user = "root";
        identityFile = "~/.ssh/keys/personal.pem";
        extraOptions = {
          PreferredAuthentications = "publickey";
        };
      };
    };
  };
}
