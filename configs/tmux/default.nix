{ config, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  programs.tmux = {
    enable = true;
    plugins = with pkgs; [
      {
        plugin = tmuxPlugins.resurrect;
      }
      {
        plugin = tmuxPlugins.yank;
      }
      {
        plugin = tmuxPlugins.open;
      }
      {
        plugin = tmuxPlugins.copycat;
      }
    ];
    extraConfig = ''
      # tmux display things in 256 colors
      set -g default-terminal "screen-256color"
      set -as terminal-overrides ',xterm*:Tc:sitm=\E[3m'

      set-option -g default-shell /run/current-system/sw/bin/fish

      # sensible yet memory-friendly scroll history
      set -g history-limit 20000

      # automatically renumber tmux windows
      set -g renumber-windows on

      # unbind default prefix and set it to Ctrl+a
      unbind C-b
      set -g prefix C-a
      bind C-a send-prefix

      # for nested tmux sessions
      bind-key -n C-a send-prefix

      # Activity Monitoring
      setw -g monitor-activity off
      set -g visual-activity off

      # Rather than constraining window size to the maximum size of any client
      # connected to the *session*, constrain window size to the maximum size of any
      # client connected to *that window*. Much more reasonable.
      setw -g aggressive-resize on

      # make delay shorter
      set -sg escape-time 0

      # tile all windows
      unbind =
      bind = select-layout tiled

      # cycle through panes
      # unbind C-a
      # unbind o # this is the default key for cycling panes
      # bind ^A select-pane -t:.+

      # make window/pane index start with 1
      set -g base-index 1
      setw -g pane-base-index 1

      set-option -g set-titles on
      set-option -g set-titles-string "#T - #W"
      # set-window-option -g automatic-rename on

      ######################
      #### Key Bindings ####
      ######################

      # reload config file
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config Reloaded!"

      # split window and fix path for tmux 1.9
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # synchronize all panes in a window
      bind y setw synchronize-panes

      # pane movement shortcuts
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      bind -r C-h select-window -t :-
      bind -r C-l select-window -t :+

      # Resize pane shortcuts
      bind -r H resize-pane -L 10i
      bind -r J resize-pane -D 10
      bind -r K resize-pane -U 10
      bind -r L resize-pane -R 10

      # Toggle kube status display for current window (Ctrl+k 8, like k8s!)
      bind -n C-k switch-client -T k8s-prefix
      bind -T k8s-prefix 8 if-shell -F "#{@kube-status}" "set-window-option -u @kube-status" "set-window-option @kube-status 1"

      # enable mouse support for switching panes/windows
      setw -g mouse on

      # switch clipboard off (else creates a race condition)
      setw -g set-clipboard off
      setw -g mode-keys vi
    ''
    + (
      if isDarwin then
        ''
          bind-key -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-and-cancel "pbcopy"
          bind-key -n -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "pbcopy"

          # Buffers to/from clipboard
          bind C-c run "tmux save-buffer - | reattach-to-user-namespace pbcopy"
          bind C-v run "tmux set-buffer (reattach-to-user-namespace pbpaste); tmux paste-buffer"
        ''
      else
        ''
          bind-key -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-and-cancel "xsel --clipboard --input"
          bind-key -n -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "xsel --clipboard --input"

          # Buffers to/from clipboard
          bind C-c run "tmux save-buffer - | reattach-to-user-namespace xsel --clipboard --input"
          bind C-v run "tmux set-buffer (reattach-to-user-namespace $(xsel --clipboard --output)); tmux paste-buffer"
        ''
    )
    + ''
      # Base16 Styling Guidelines:

      base00=default   # - Default
      base01='#151515' # - Lighter Background (Used for status bars)
      base02='#202020' # - Selection Background
      base03='#909090' # - Comments, Invisibles, Line Highlighting
      base04='#505050' # - Dark Foreground (Used for status bars)
      base05='#D0D0D0' # - Default Foreground, Caret, Delimiters, Operators
      base06='#E0E0E0' # - Light Foreground (Not often used)
      base07='#F5F5F5' # - Light Background (Not often used)
      base08='#AC4142' # - Variables, XML Tags, Markup Link Text, Markup Lists, Diff Deleted
      base09='#D28445' # - Integers, Boolean, Constants, XML Attributes, Markup Link Url
      base0A='#F4BF75' # - Classes, Markup Bold, Search Text Background
      base0B='#90A959' # - Strings, Inherited Class, Markup Code, Diff Inserted
      base0C='#75B5AA' # - Support, Regular Expressions, Escape Characters, Markup Quotes
      base0D='#6A9FB5' # - Functions, Methods, Attribute IDs, Headings
      base0E='#AA759F' # - Keywords, Storage, Selector, Markup Italic, Diff Changed
      base0F='#8F5536' # - Deprecated, Opening/Closing Embedded Language Tags, e.g. <? php ?>

      set -g status-left-length 32
      set -g status-right-length 150
      set -g status-interval 5

      # default statusbar colors
      set-option -g status-style fg=$base02,bg=$base00,default

      set-window-option -g window-status-style fg=$base03,bg=$base00
      set-window-option -g window-status-format " #I #W"

      # active window title colors
      set-window-option -g window-status-current-style fg=$base0C,bg=$base00
      set-window-option -g window-status-current-format " #[bold]#W"

      # pane border colors
      set-window-option -g pane-active-border-style fg=$base0C
      set-window-option -g pane-border-style fg=$base03

      # message text
      set-option -g message-style bg=$base00,fg=$base0C

      # pane number display
      set-option -g display-panes-active-colour $base0C
      set-option -g display-panes-colour $base01

      # clock
      set-window-option -g clock-mode-colour $base0C

      tm_session_name="#[default,bg=$base00,fg=$base0E] #S "
      set -g status-left "$tm_session_name"
    ''
    + (
      if isDarwin then
        ''
          tm_battery="#[fg=$base0F,bg=$base00] ♥ #(pmset -g batt | grep InternalBattery | awk '{print $3}' | sed 's/;$//')"
        ''
      else
        ''
          tm_battery="#[fg=$base0F,bg=$base00] ♥ #(acpi --battery | awk \'{gsub(\",\", \"\"); print \$4}\')"
        ''
    )
    + ''
      tm_date="#[default,bg=$base00,fg=$base0C] %I:%M %p %Z"
      tm_host="#[fg=$base0E,bg=$base00] #h "
      tm_kube_status="#[fg=$base0D,bg=$base00]#{?@kube-status, #(command -v kubectl >/dev/null 2>&1 && kubectl config current-context 2>/dev/null | sed 's/^/⎈ /'),}"
      set -g status-right "$tm_tunes $tm_kube_status $tm_battery $tm_date $tm_host"
    '';
  };
}
