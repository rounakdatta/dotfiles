{ config, lib, ... }:

# Lyric's `mic` CLI, installed from its GitHub releases.
#
# The laptop does NOT use this: trueswiftie takes mic from the lyric-tech/mic
# tap (hosts/trueswiftie/software.nix), and a hand-installed copy in
# ~/.local/bin would shadow the Homebrew one depending on PATH order. This
# module exists for hosts with no Homebrew to speak of — festie, the agentfest
# container — where mic is not optional: configs/claude declares the
# `notprod-lyric-deploy` MCP server as `command = "mic"`, and that declaration
# is not platform-gated, so it lands on Linux hosts too. Without mic on PATH
# the server is declared and dead.
#
# mic ships statically-linked Linux binaries as of 0.7.0 (lyric-tech/mic#55),
# which is what makes this possible at all — there is no glibc loader at
# /lib64 in a Nix-built container.

let
  cfg = config.programs.lyric-mic;
  binDir = "${config.home.homeDirectory}/.local/bin";
in
{
  options.programs.lyric-mic = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install the mic CLI into ~/.local/bin from lyric-tech/mic releases.
        Leave this off wherever Homebrew already provides mic.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "latest";
      description = ''
        Release tag to install, or "latest" to resolve against GitHub on every
        activation. "latest" matches how agentfest tracks claude-code and
        codeman: the machine follows upstream by re-activating rather than by
        editing a pin, and the marker file below means it only re-downloads
        when upstream has actually moved.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Deliberately ahead of any Homebrew prefix on PATH. On a host that carries
    # both (festie installs mic this way AND has brew available), this copy is
    # the reliable one — it needs nothing but gh — so it should win by default.
    # A brew-installed mic stays reachable at $(brew --prefix)/bin/mic for
    # explicit testing.
    home.sessionPath = [ binDir ];

    # entryAfter writeBoundary is the same slot the go/cargo/npm package
    # modules use — after home-manager has finished linking the generation, so
    # gh and its config are in place.
    # The whole body runs in a SUBSHELL, and that is load-bearing rather than
    # stylistic. home-manager concatenates every home.activation block into one
    # bash script, so a bare `exit 0` here does not "skip this module" — it ends
    # the entire activation run, silently and with status 0. Every step ordered
    # after this one is simply never reached: installPackages, linkGeneration,
    # mergeGlobalMcpServers, npmPackages, restoreAtuin, syncPrivateSkills,
    # syncClaudeDocs, writeProjectLocalMcpServers.
    #
    # That failure is worse than it sounds, because the early exit people
    # actually hit is the *success* path: `mic already installed`. A fresh
    # volume activates cleanly (mic gets downloaded, control falls through the
    # bottom of the block), and every activation after that truncates. The
    # machine converges exactly once and then stops, keeping ~/.claude,
    # ~/.config/fish and ~/.config/tmux pinned to the generation that first
    # installed mic — which on festie means dangling symlinks into a store path
    # the next image no longer carries. Nothing logs a warning, because exiting
    # 0 is indistinguishable from finishing.
    #
    # Same pattern as configs/pass, for the same reason.
    home.activation.installLyricMic = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      (
        export PATH="${config.home.path}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:$PATH"

        # Every failure below is soft. This runs during container startup on
        # festie, and activation gates whether the machine becomes usable at
        # all — refusing to boot because GitHub was briefly unreachable would be
        # a far worse outcome than running yesterday's mic.
        if ! command -v gh >/dev/null 2>&1; then
          echo "mic: gh unavailable, skipping install"
          exit 0
        fi
        if ! gh auth status >/dev/null 2>&1; then
          echo "mic: gh not authenticated (run 'gh auth login'), skipping install"
          exit 0
        fi

        case "$(uname -s)" in
          Linux) micOS=linux ;;
          Darwin) micOS=darwin ;;
          *) echo "mic: unsupported OS $(uname -s), skipping"; exit 0 ;;
        esac
        case "$(uname -m)" in
          x86_64 | amd64) micArch=amd64 ;;
          aarch64 | arm64) micArch=arm64 ;;
          *) echo "mic: unsupported architecture $(uname -m), skipping"; exit 0 ;;
        esac

        micTarget="${cfg.version}"
        if [ "$micTarget" = "latest" ]; then
          micTarget="$(gh release view --repo lyric-tech/mic --json tagName -q .tagName 2>/dev/null || true)"
          if [ -z "$micTarget" ]; then
            echo "mic: could not resolve the latest release; keeping the current install"
            exit 0
          fi
        fi

        micMarker="${binDir}/.mic-version"
        if [ "$(cat "$micMarker" 2>/dev/null || true)" = "$micTarget" ] && [ -x "${binDir}/mic" ]; then
          echo "mic $micTarget already installed"
          exit 0
        fi

        mkdir -p "${binDir}"
        micTmp="$(mktemp -d)"
        # Streamed straight out of gh into tar: the asset lives on a private
        # repo, so a plain curl would 404 without a token. gh already holds one.
        if gh release download "$micTarget" \
             --repo lyric-tech/mic \
             --pattern "mic_''${micOS}_''${micArch}.tar.gz" \
             --output - 2>/dev/null | tar xz -C "$micTmp" mic; then
          install -m 0755 "$micTmp/mic" "${binDir}/mic"
          printf '%s\n' "$micTarget" > "$micMarker"
          echo "mic: installed $micTarget"
        else
          echo "mic: download of $micTarget failed; leaving the existing install in place"
        fi
        rm -rf "$micTmp"
      ) || true
    '';
  };
}
