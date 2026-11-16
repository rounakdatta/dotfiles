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

      # --omit-dir-times: Nextcloud's File Provider keeps its own folder times,
      # so copying the vault's would rewrite every folder on every run.
      mirror() {
        rsync --archive --omit-dir-times --delete \
          --exclude=/.stfolder --exclude=/.stversions --exclude=/.stignore \
          --exclude=.DS_Store \
          --exclude=/.obsidian/workspace.json --exclude=/.obsidian/workspace-mobile.json \
          "$@" "$vault/" "''${accounts[0]}/backups/obsidian/"
      }

      # A run that would delete more than 50 files deletes none and fails, so
      # a mass deletion upstream (a bad sync, say) never reaches the backup on
      # its own, not even 50 at a time. A deliberate one goes through with
      # OBSIDIAN_BACKUP_FORCE=1 obsidian-backup.
      deletions="$(mirror --dry-run --itemize-changes | grep -c '^\*deleting' || true)"
      if [ "$deletions" -gt 50 ] && [ -z "''${OBSIDIAN_BACKUP_FORCE:-}" ]; then
        echo "obsidian-backup: $deletions files would be deleted from the backup; nothing done. If that is meant: OBSIDIAN_BACKUP_FORCE=1 obsidian-backup" >&2
        exit 1
      fi

      # Quiet when there is nothing to copy, which is most runs.
      updated="$(mirror --itemize-changes | grep -c . || true)"
      if [ "$updated" -gt 0 ]; then
        printf 'obsidian-backup: %(%F %T)T, %s updated\n' -1 "$updated"
      fi
    '';
  };
in
# Darwin-only: the vault is on trueswiftie. A no-op on NixOS and festie.
lib.mkIf isDarwin {
  launchd.agents.obsidian-backup = {
    enable = true;
    config = {
      ProgramArguments = [ "${backup}/bin/obsidian-backup" ];
      # Every 15 minutes, so the backup trails the vault by no more than that;
      # intervals missed asleep run once on wake. RunAtLoad adds a run at every
      # login, and one as soon as a switch installs it.
      StartInterval = 900;
      RunAtLoad = true;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
