{ ... }: {
  programs.ssh = {
    enable = true;
    # Explicitly disable default config to silence deprecation warning
    enableDefaultConfig = false;

    # A Host line takes several patterns, so both forges share one block.
    settings."github.com gitlab.com" = {
      User = "rounakdatta";
      IdentityFile = "~/.ssh/keys/personal.pem";
      PreferredAuthentications = "publickey";
    };
  };
}
