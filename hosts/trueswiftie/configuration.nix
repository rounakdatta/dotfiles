{ inputs, config, pkgs, lib, user, ... }:

{
  nix.settings = {
    # this is required because flakes hasn't graduated into a stable feature yet
    experimental-features = [ "nix-command" "flakes" ];
  };

  nix.gc = {
    automatic = true;
  };

  # nix-daemon is now managed automatically by nix-darwin

  # Fix for GID mismatch after nix-darwin upgrade
  # The default nixbld GID changed from 30000 to 350, but we keep the existing one
  ids.gids.nixbld = 30000;

  # Set primary user for Homebrew and other user-specific options
  system.primaryUser = user.username;

  networking.hostName = "trueswiftie";

  users.users.${user.username} = {
    # workaround for https://github.com/nix-community/home-manager/issues/4026
    home = "/Users/${user.username}";
    packages = with pkgs; [
      git
    ];
    shell = pkgs.fish;
    ignoreShellProgramCheck = true;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  services.nextdns = {
    enable = true;
    arguments = [ "-config" "379869" ]; # yeah feel free to use mine, just drop me a line that you're
  };

  # TODO: generalize the username here
  system.activationScripts.postActivation.text = ''
    chsh -s /run/current-system/sw/bin/fish ${user.username}
  '';

  system.activationScripts.extraActivation.text = ''
    # there's no going back from Apple Silicon
    softwareupdate --install-rosetta --agree-to-license

    # yes, we live up in the clouds
    /opt/homebrew/bin/gcloud components install gke-gcloud-auth-plugin

    # Android SDK setup - accept licenses first, then install
    # SDK installs to /opt/homebrew/share/android-commandlinetools by default
    yes | /opt/homebrew/bin/sdkmanager --licenses || true
    /opt/homebrew/bin/sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.0.0" "cmdline-tools;latest"
  '';
}
