{ pkgs, lib, ... }:

let
  # Stable tools from nixpkgs (don't need frequent updates)
  # These are well-maintained in nixpkgs and reproducibility matters
  stableNpmTools = with pkgs.nodePackages; [
    # Language servers and build-critical tools
    typescript-language-server
    vscode-langservers-extracted

    # Common stable utilities
    prettier
    eslint
  ];

  # Packages to install globally via npm
  # These are kept up-to-date and you can upgrade them anytime with: npm update -g
  npmGlobalPackages = [
    "happy-coder"
    # Add more packages here as needed
  ];

  # Script to install npm packages globally
  installNpmGlobals = pkgs.writeShellScriptBin "install-npm-globals" ''
    #!/usr/bin/env bash
    echo "📦 Installing global npm packages..."

    # Set PATH to include homebrew binaries
    export PATH="/opt/homebrew/bin:$PATH"

    # Use the homebrew node since that's what you have configured
    npm install -g ${pkgs.lib.concatStringsSep " " npmGlobalPackages}

    echo "✅ Done! Global npm packages installed."
  '';

in {
  home.packages = stableNpmTools ++ [
    installNpmGlobals
  ];

  # Auto-install npm globals on home-manager activation
  # This ensures your npm globals are always in sync across rebuilds
  home.activation.installNpmPackages = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Syncing npm global packages..."
    $DRY_RUN_CMD ${installNpmGlobals}/bin/install-npm-globals
  '';
}
