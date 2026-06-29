{ lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;

  # Build the ClaudePets.saver bundle: an ObjC ScreenSaverView (claude-pets.m)
  # compiled against Cocoa + ScreenSaver, plus the two bot logos shared with the
  # Hammerspoon overlay (configs/hammerspoon). Code signing is deferred to the
  # activation step below, where the system codesign signs the copy in place.
  claudePetsSaver = pkgs.stdenv.mkDerivation {
    pname = "claude-pets-screensaver";
    version = "1.0";
    dontUnpack = true;

    buildPhase = ''
      runHook preBuild
      clang -bundle -fobjc-arc -mmacosx-version-min=12.0 \
        -framework Cocoa -framework ScreenSaver -framework Foundation \
        -o ClaudePets ${./claude-pets.m}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      c="$out/ClaudePets.saver/Contents"
      mkdir -p "$c/MacOS" "$c/Resources"
      cp ClaudePets "$c/MacOS/ClaudePets"
      cp ${./Info.plist} "$c/Info.plist"
      cp ${../hammerspoon/claudecode-color.png} "$c/Resources/claudecode-color.png"
      cp ${../hammerspoon/claudecode-gray.png} "$c/Resources/claudecode-gray.png"
      runHook postInstall
    '';
  };
in
# Darwin-only: a .saver is a macOS bundle. On NixOS this module is a no-op.
lib.mkIf isDarwin {
  # Install + sign the saver into ~/Library/Screen Savers on every activation.
  # We re-copy (not symlink) because the sandboxed legacyScreenSaver host loads
  # bundles from the user's Library, not /nix/store; chmod +w lets the system
  # codesign re-sign the store's read-only copy in place (arm64 refuses to load
  # an unsigned bundle).
  #
  # NOT automated: selecting it as the *active* screensaver. macOS 26 only
  # registers a freshly-dropped .saver for selection once the Screen Saver
  # settings pane has scanned it, with no headless trigger — so enabling it is a
  # one-time manual click (System Settings > Screen Saver > ClaudePets). It then
  # persists across reboots and rebuilds (the bundle updates in place).
  home.activation.installClaudePetsScreensaver =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      saver="$HOME/Library/Screen Savers/ClaudePets.saver"
      $DRY_RUN_CMD mkdir -p "$HOME/Library/Screen Savers"
      $DRY_RUN_CMD rm -rf "$saver"
      $DRY_RUN_CMD cp -R ${claudePetsSaver}/ClaudePets.saver "$saver"
      $DRY_RUN_CMD chmod -R u+w "$saver"
      $DRY_RUN_CMD /usr/bin/codesign --force --sign - "$saver" 2>/dev/null || true
    '';
}
