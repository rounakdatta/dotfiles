{ config, lib, pkgs, ... }:

# The daemon itself, kept running by launchd: what the phone and the desktop
# app reach on this Mac, whether or not the app is open. On festie, agentfest
# runs the daemon, so this stays off there.
#
# It starts through a fish login shell, because Paseo spawns claude, codex,
# opencode and gh by name, so agents get the PATH a terminal here has. And the
# plist names profile paths, never the store, so it reads the same after every
# switch and a switch never restarts the daemon under a running agent; a new
# launcher takes over at the next start (login, reboot, crash).
let
  cfg = config.programs.paseo;
  bin = "${config.home.profileDirectory}/bin";
  log = "${config.home.homeDirectory}/Library/Logs/paseo-daemon.log";

  launcher = pkgs.writeShellApplication {
    name = "paseo-daemon";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      status() { paseo daemon status --json 2>/dev/null | jq -r ".$1"; }

      if ! command -v paseo >/dev/null 2>&1; then
        echo "paseo-daemon: paseo is not installed" >&2
        sleep 300 # rather than let launchd retry every ten seconds
        exit 1
      fi

      # `paseo-daemon apply`: settings and projects reach a daemon only
      # through its API, so a switch, which leaves the daemon running, hands
      # them over this way.
      if [ "''${1:-}" = apply ]; then
        if [ "$(status connectedDaemon)" = reachable ]; then
          paseo-apply-declared
        fi
        exit 0
      fi

      # With another daemon already serving ~/.paseo (started by hand, by
      # `paseo start`, or by the desktop app), `paseo daemon run` exits 0 at
      # once, and launchd would turn that into a restart every ten seconds.
      # Wait for that one to go instead, then take over.
      while [ "$(status localDaemon)" = running ]; do
        sleep 30
      done

      # Once the new daemon answers, hand it what the dotfiles declare, as
      # agentfest does after every start.
      (
        for _ in $(seq 60); do
          sleep 5
          if [ "$(status connectedDaemon)" = reachable ]; then
            paseo-apply-declared
            break
          fi
        done
      ) &

      exec paseo daemon run
    '';
  };
in
{
  options.programs.paseo.service.enable = lib.mkEnableOption ''
    the Paseo daemon as a launchd agent on macOS, running from login whether
    or not the desktop app is open'';

  config = lib.mkIf (cfg.enable && cfg.service.enable) {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin && config.programs.fish.enable;
        message = "programs.paseo.service runs the daemon under launchd through a fish login shell: it needs macOS and programs.fish.";
      }
    ];

    home.packages = [ launcher ];

    launchd.agents.paseo = {
      enable = true;
      config = {
        ProgramArguments = [ "${bin}/fish" "--login" "--command" "exec ${bin}/paseo-daemon" ];
        RunAtLoad = true;
        KeepAlive = true;
        # The daemon writes its own log, ~/.paseo/daemon.log, and the same lines
        # to stdout; launchd never rotates a log, so stdout is dropped. stderr
        # keeps the launcher's messages and anything the daemon dies with.
        StandardOutPath = "/dev/null";
        StandardErrorPath = log;
      };
    };

    home.activation.paseoApplyDeclared = lib.hm.dag.entryAfter [ "setupLaunchAgents" "paseoConfig" ] ''
      run ${bin}/fish --login --command '${pkgs.coreutils}/bin/timeout 120 ${bin}/paseo-daemon apply' || true
    '';
  };
}
