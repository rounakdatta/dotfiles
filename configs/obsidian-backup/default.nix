{ config, lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  log = "${config.home.homeDirectory}/Library/Logs/obsidian-backup.log";

  # Syncthing keeps ~/Obsidian in step between this Mac and the phone; this is
  # the copy that lives on neither. One way only: the vault goes up to
  # Nextcloud and nothing comes back, so the two never fight over a file the
  # way they did when the vault lived in Nextcloud's own folder. Nextcloud's
  # version history and trash bin are what make the mirror a backup.
  backup = pkgs.writeShellApplication {
    name = "obsidian-backup";
    runtimeInputs = [ pkgs.rsync ];
    text = ''
      vault="$HOME/Obsidian"
      # The folder is named after the account, with U+2024 standing in for the
      # dots of the host, so find it rather than spell it out.
      shopt -s nullglob
      accounts=("$HOME"/Library/CloudStorage/Nextcloud-*)

      # A missing vault would mirror as "delete everything".
      if [ ! -d "$vault/.obsidian" ] || [ "''${#accounts[@]}" -ne 1 ]; then
        echo "obsidian-backup: no vault at $vault, or not exactly one Nextcloud account; nothing done" >&2
        exit 1
      fi

      # --max-delete: a mass deletion upstream, say a bad sync, stops here and
      # fails the run, rather than emptying the backup too.
      rsync --archive --delete --max-delete=50 \
        --exclude=/.stfolder --exclude=/.stversions --exclude=/.stignore \
        --exclude=.DS_Store \
        --exclude=/.obsidian/workspace.json --exclude=/.obsidian/workspace-mobile.json \
        "$vault/" "''${accounts[0]}/backups/obsidian/"
      printf 'obsidian-backup: %(%F %T)T, up to date\n' -1
    '';
  };
in
# Darwin-only: the vault is on trueswiftie. A no-op on NixOS and festie.
lib.mkIf isDarwin {
  launchd.agents.obsidian-backup = {
    enable = true;
    config = {
      ProgramArguments = [ "${backup}/bin/obsidian-backup" ];
      # Nightly; launchd runs a night it missed when the Mac next wakes.
      # RunAtLoad adds a run at every login, and one as soon as a switch
      # installs it.
      StartCalendarInterval = [{ Hour = 3; Minute = 30; }];
      RunAtLoad = true;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
