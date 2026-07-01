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
  # Install the saver into ~/Library/Screen Savers, but only when the built
  # bundle actually changes: the Nix store path is a perfect change token, so a
  # routine `darwin-rebuild switch` is a true no-op here — no re-copy, no re-sign.
  #
  # We copy (not symlink via home.file) and sign in place because the bundle Nix
  # produces is not a validly signed *bundle*: only the Mach-O is linker-signed,
  # with no sealed _CodeSignature, so `codesign --verify` on the store path fails
  # ("code has no resources but signature indicates they must be present"). Full
  # bundle signing needs the system codesign, which a hermetic Nix build can't
  # run (and sigtool only signs Mach-O, not bundle resources). arm64 won't load
  # an unsealed bundle, so we seal it here — which requires a writable copy.
  #
  # NOT automated: selecting it as the *active* screensaver. macOS 26 only
  # registers a freshly-dropped .saver for selection once the Screen Saver
  # settings pane has scanned it, with no headless trigger — so enabling it is a
  # one-time manual click (System Settings > Screen Saver > ClaudePets). It then
  # persists across reboots and rebuilds (the bundle updates in place).
  home.activation.installClaudePetsScreensaver =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      src="${claudePetsSaver}/ClaudePets.saver"
      dest="$HOME/Library/Screen Savers/ClaudePets.saver"
      stamp="$HOME/Library/Screen Savers/.ClaudePets.nix-source"
      if [ ! -e "$dest" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$src" ]; then
        $DRY_RUN_CMD mkdir -p "$HOME/Library/Screen Savers"
        $DRY_RUN_CMD rm -rf "$dest"
        $DRY_RUN_CMD cp -R "$src" "$dest"
        $DRY_RUN_CMD chmod -R u+w "$dest"
        $DRY_RUN_CMD /usr/bin/codesign --force --sign - "$dest" 2>/dev/null || true
        $DRY_RUN_CMD sh -c 'printf "%s" "$1" > "$2"' _ "$src" "$stamp"
      fi
    '';
}
