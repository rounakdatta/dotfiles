{ config, lib, pkgs, ... }:

# festie-doctor — assert the container actually converged.
#
# festie is the one host where "did home-manager finish?" is a question worth
# asking automatically. Its Nix store lives in an image layer while $HOME lives
# on a PVC, so the two can disagree: activation that stops early leaves the home
# directory pinned to a generation the running image no longer carries, and
# every symlink in it dangles. That is not hypothetical — it is exactly what
# configs/mic's `exit 0` caused, silently, on every boot for days, while the
# entrypoint reported success because exiting 0 is indistinguishable from
# finishing.
#
# Deliberately hash-free, so it needs no pinned version and stays correct across
# every image bump on its own. A version-stamped doctor is a doctor nobody
# updates. Two questions are asked separately, because they fail for different
# reasons and a single check would report the wrong cause for half of them:
#
#   1. is the active generation the one $AGENTFEST_HOME_ACTIVATION baked in?
#      (no  =>  activation did not run this boot, or something was activated by
#      hand)
#   2. does every managed file resolve to the ACTIVE generation's copy?
#      (no  =>  activation started but never reached linkGeneration)
#
# The bug this exists for failed (2) while passing (1): the profile generation
# is created at writeBoundary, long before the step that relinks the files, so a
# run that dies in between leaves a current-looking generation and a home
# directory still pointing at the previous one.
#
# The shell body below is deliberately ASCII-only: writeShellApplication runs
# shellcheck at build time, and shellcheck's output encoder dies on a non-ASCII
# character in any line it wants to quote back at you.

let
  cfg = config.programs.festie-doctor;

  # Read straight off the codeman module so the two can never disagree about
  # which cases exist.
  cases = config.programs.codeman.linkedCases;

  # The load-bearing files, each with the capability it gates. Kept explicit
  # rather than derived from config.home.file: that would also enumerate the
  # whole skills tree, and the point here is a short, readable verdict on the
  # things whose absence breaks the machine in a way that is hard to diagnose
  # from the symptom.
  managedFiles = {
    ".claude/settings.json" = "claude permissions, hooks and effort level";
    ".config/fish/config.fish" = "shell configuration";
    ".config/git/config" = "git identity, signing and url rewrites";
    ".config/gopass/config" = "gopass mount, and so every pass-backed MCP server";
    ".config/tmux/tmux.conf" = "tmux keys and status line";
    ".gnupg/gpg-agent.conf" = "pinentry, and so whether pass can decrypt at all";
  };

  # Priming the agent is a separate command from checking it, because it needs
  # something the checker never has: a terminal. pinentry-curses draws on the
  # tty, so this cannot run from an activation step, a hook, or an agent's tool
  # call - only from a shell someone is actually looking at.
  unlock = pkgs.writeShellApplication {
    name = "festie-unlock";
    runtimeInputs = with pkgs; [ coreutils findutils gnupg ];
    text = ''
      if [ ! -t 1 ]; then
        echo "festie-unlock needs a terminal; pinentry-curses draws on the tty." >&2
        echo "Run it from a shell pane, not from a script or an agent tool call." >&2
        exit 1
      fi
      GPG_TTY="$(tty)"
      export GPG_TTY

      # Sign and decrypt are cached SEPARATELY, keyed by keygrip. This is the
      # trap worth automating away: unlocking for `git commit` primes the [SC]
      # key only, and leaves pass, gopass and every pass-backed MCP server just
      # as locked as before - with no error until something quietly fails to
      # start. Prime both, once, deliberately.

      echo "priming the signing key..."
      printf 'festie-unlock' | gpg --clearsign >/dev/null

      echo "priming the decryption key..."
      secret="$(find "$HOME/.password-store" -name '*.gpg' -print -quit 2>/dev/null || true)"
      if [ -n "$secret" ]; then
        gpg --decrypt "$secret" >/dev/null
      else
        echo "no password store entries found; decryption key left unprimed" >&2
      fi

      # Report the capability, not gpg-agent's key-cache flag: decryption can be
      # satisfied from the passphrase cache without the key cache ever showing
      # it, so `keyinfo` reports "locked" on a key that works. See the doctor.
      echo
      if printf 'x' | gpg --batch --no-tty --clearsign >/dev/null 2>&1; then
        printf '  \033[32mready\033[0m   signing (git commit)\n'
      else
        printf '  \033[31mlocked\033[0m  signing (git commit)\n'
      fi
      if [ -n "$secret" ] && gpg --batch --no-tty --decrypt "$secret" >/dev/null 2>&1; then
        printf '  \033[32mready\033[0m   decryption (pass, gopass, MCP servers)\n'
      else
        printf '  \033[31mlocked\033[0m  decryption (pass, gopass, MCP servers)\n'
      fi
      echo
      echo "Cached until this pod restarts. Re-run after any deploy."
    '';
  };

  doctor = pkgs.writeShellApplication {
    name = "festie-doctor";
    # Declared rather than left to the inherited PATH: this runs on a machine
    # whose whole failure mode is an environment that did not come up the way it
    # should have, so it must not depend on one.
    runtimeInputs = with pkgs; [ coreutils findutils gnugrep git gnupg jq ncurses openssh ];
    text = ''
      fails=0
      pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
      fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fails=$((fails + 1)); }
      note() { printf '        %s\n' "$1"; }

      baked="''${AGENTFEST_HOME_ACTIVATION:-}"
      current="$(readlink -f "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null || true)"

      # A file that merely exists proves nothing: after a truncated activation
      # the old symlink still resolves, right up until the store path behind it
      # vanishes with the next image. Comparing the target to the ACTIVE
      # generation's own copy is what catches a home directory that has stopped
      # tracking it.
      #
      # Compared against the active generation rather than the image's, and the
      # two are asserted equal separately below. They diverge for two very
      # different reasons - activation never finished, or someone activated a
      # locally built generation by hand - and collapsing them into one check
      # reports the wrong cause for half the failures.
      check_managed() {
        local rel="$1" why="$2" want have
        want="$(readlink -f "$current/home-files/$rel" 2>/dev/null || true)"
        have="$(readlink -f "$HOME/$rel" 2>/dev/null || true)"
        if [ -z "$have" ]; then
          fail "$HOME/$rel is missing or dangling"
          note "gates: $why"
        elif [ -z "$want" ]; then
          note "$HOME/$rel not shipped by this image; skipped"
        elif [ "$want" = "$have" ]; then
          pass "$HOME/$rel"
        else
          fail "$HOME/$rel points at a stale generation"
          note "gates: $why"
        fi
      }

      # Derived from programs.codeman.linkedCases rather than listed here, so a
      # case added there is checked here automatically. The previous version
      # hardcoded personal and work, and byoc landed without the doctor
      # noticing - a coverage gap that is invisible precisely because the tool
      # still reports all-clear.
      #
      # All three assertions matter for a case to be usable: the directory has
      # to exist, Codeman has to know the name, and .mcp.json has to be there -
      # project MCP resolves from the case directory and does not walk up, so a
      # case without one silently starts with no servers.
      check_case() {
        local name="$1" path="$2"
        if [ ! -d "$path" ]; then
          fail "case $name: $path does not exist"
        elif ! grep -q "\"$name\"" "$HOME/.codeman/linked-cases.json" 2>/dev/null; then
          fail "case $name is not registered in linked-cases.json"
        elif [ ! -f "$path/.mcp.json" ]; then
          fail "case $name has no .mcp.json; it would start with no MCP servers"
        else
          pass "case $name -> $path"
        fi
      }

      printf '\n=== activation ===\n'
      if [ -z "$current" ]; then
        fail "no active home-manager generation; activation has never run here"
      elif [ -z "$baked" ]; then
        note "AGENTFEST_HOME_ACTIVATION unset; not inside the agentfest image"
        pass "active generation $current"
      elif [ "$current" = "$baked" ]; then
        pass "active generation is the one this image baked"
      else
        fail "active generation is not the image's"
        note "image:  $baked"
        note "active: $current"
        note "either activation did not run this boot, or a generation was activated by hand"
      fi

      printf '\n=== home-manager files track the active generation ===\n'
      if [ -n "$current" ] && [ -d "$current/home-files" ]; then
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList (f: why: ''check_managed "${f}" "${why}"'') managedFiles)}
      else
        fail "skipped; no active generation to compare against"
      fi

      printf '\n=== capabilities ===\n'
      # Report the mode; do not assert a particular one. The first version of
      # this check grepped for the literal string "bypassPermissions", so the
      # day that setting legitimately changed to "auto" the doctor reported a
      # broken machine - on a machine that was fine. A checker that pins a value
      # it does not own becomes a liar at the first intentional change, and the
      # symlink section above already proves this file is the nix-managed one.
      #
      # What it CAN assert is that the two halves of the decision agree, because
      # there are two files, two vocabularies and one concept:
      #
      #   ~/.claude/settings.json   permissions.defaultMode   a bare 'claude'
      #   ~/.codeman/settings.json  claudeMode                every Codeman session
      #
      # Codeman wins wherever they differ - it turns its key into an explicit CLI
      # flag at spawn, and a command-line argument outranks a settings file - so a
      # disagreement means the mode you read in one file is NOT the mode the
      # machine runs, with nothing on the Claude side able to show it.
      #
      # This is also the ONLY coverage ~/.codeman/settings.json gets. It cannot be
      # a home.file (Codeman rewrites it at runtime, see configs/codeman), so the
      # managed-files section above cannot vouch for it. An activation that dies
      # before codemanClaudePermissionMode leaves Codeman on its old mode while
      # .claude/settings.json already carries the new one - which is a mismatch,
      # and therefore caught here.
      #
      # Still no pinned policy: the case statement below is a mapping between two
      # tools' names for the same mode, which stays true whichever mode is chosen.
      # Only a MISMATCH fails.
      mode="$(jq -r '.permissions.defaultMode // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)"
      codeman_mode="$(jq -r '.claudeMode // empty' "$HOME/.codeman/settings.json" 2>/dev/null || true)"
      case "$codeman_mode" in
        dangerously-skip-permissions) codeman_as_claude="bypassPermissions" ;;
        auto)                         codeman_as_claude="auto" ;;
        normal | allowedTools)        codeman_as_claude="default" ;;
        *)                            codeman_as_claude="$codeman_mode" ;;
      esac

      if [ -z "$mode" ]; then
        fail "claude settings.json has no permissions.defaultMode - missing, or not the nix-managed one"
      elif [ -z "$codeman_mode" ]; then
        # Absent is not neutral. Codeman falls back to its OWN default,
        # dangerously-skip-permissions, whenever the key is missing or the file
        # cannot be parsed - so this reads as "no opinion" while granting the most
        # permissive mode there is.
        fail "codeman settings.json has no claudeMode - Codeman falls back to bypass"
        note "activation should have written it; see configs/codeman"
        note "bare claude is on: $mode"
      elif [ "$mode" = "$codeman_as_claude" ]; then
        pass "claude permission mode: $mode (both layers agree)"
      else
        fail "permission mode disagrees between layers, and Codeman is the one that wins"
        note "bare claude   ~/.claude/settings.json   $mode"
        note "codeman       ~/.codeman/settings.json  $codeman_mode (= $codeman_as_claude)"
        note "every session you start from the UI runs the codeman one"
      fi
      if grep -q "pinentry" "$HOME/.gnupg/gpg-agent.conf" 2>/dev/null; then
        pass "gpg-agent has a pinentry-program"
      else
        fail "no pinentry-program; pass, gopass and pass-backed MCP servers cannot decrypt"
      fi
      if command -v clear >/dev/null 2>&1 && infocmp -1 "''${TERM:-xterm-256color}" >/dev/null 2>&1; then
        pass "clear and terminfo for TERM=''${TERM:-unset}"
      else
        fail "clear or terminfo missing for TERM=''${TERM:-unset}"
      fi

      printf '\n=== cases ===\n'
      ${lib.concatStringsSep "\n      " (lib.mapAttrsToList (name: path: ''check_case "${name}" "${path}"'') cases)}

      # Loud on purpose. The passphrase cache lives in gpg-agent's memory, so it
      # dies with the pod - every deploy locks the machine again. Left silent,
      # the way you find out is a pass-backed MCP server that simply never
      # appears, which looks like a config problem and is not one.
      #
      # Sign and decrypt are cached separately by keygrip, so both are reported:
      # unlocking for a commit does nothing for pass.
      printf '\n=== gpg agent (cache dies with the pod) ===\n'
      # Probe the CAPABILITY, never the agent's bookkeeping. `keyinfo --list`
      # reports gpg-agent's private-KEY cache, and decryption can satisfy itself
      # from the separate PASSPHRASE cache without ever populating it - observed
      # here reporting the [E] key as uncached while `pass show` worked fine. A
      # checker that cries wolf is worse than no checker, so ask the only
      # question that matters: does the operation complete with no tty to prompt
      # on? That is precisely the situation an MCP server is spawned into.
      before_gpg="$fails"
      if printf 'x' | gpg --batch --no-tty --clearsign >/dev/null 2>&1; then
        pass "signing works with no tty"
      else
        fail "signing would prompt; git commit will block"
      fi
      probe="$(find "$HOME/.password-store" -name '*.gpg' -print -quit 2>/dev/null || true)"
      if [ -z "$probe" ]; then
        note "password store has no entries; decryption not probed"
      elif gpg --batch --no-tty --decrypt "$probe" >/dev/null 2>&1; then
        pass "decryption works with no tty (pass, gopass, MCP servers)"
      else
        fail "decryption would prompt; pass-backed MCP servers will not start"
      fi
      if [ "$fails" -gt "$before_gpg" ]; then
        note "run 'festie-unlock' in a terminal to prime both keys"
      fi

      # Transport must work with the GPG key still locked, which is the whole
      # reason festie routes github over ssh. It is checked below precisely
      # because it must pass even when the section above fails.
      printf '\n=== git transport with the key locked ===\n'
      if [ -e "$HOME/.gitconfig.https" ]; then
        fail "$HOME/.gitconfig.https present; it races the ssh insteadOf rule"
      else
        pass "no stale PAT include"
      fi
      if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
         timeout 45 git ls-remote https://github.com/rounakdatta/dotfiles HEAD >/dev/null 2>&1; then
        pass "git ls-remote succeeds without unlocking anything"
      else
        fail "git ls-remote failed; transport depends on something unavailable at boot"
      fi

      printf '\n'
      if [ "$fails" -eq 0 ]; then
        printf '\033[32mconverged - all checks passed\033[0m\n\n'
      else
        printf '\033[31m%d check(s) failed\033[0m\n\n' "$fails"
      fi
      [ "$fails" -eq 0 ]
    '';
  };
in
{
  options.programs.festie-doctor = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install festie-doctor, a convergence check for the agentfest container.
        Only meaningful where $AGENTFEST_HOME_ACTIVATION is set.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ doctor unlock ];
  };
}
