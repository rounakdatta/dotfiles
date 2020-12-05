if [ -n "$TMUX_PANE" ]
  set HISTFILE $HOME/.local/share/fish/fish_history_tmux_$TMUX_PANE
end

# set java home
set JAVA_HOME /usr/libexec/java_home

# set local hive and remote connections through beeline correct
set HADOOP_HOME ~/tooling/hadoop-2.5.1
set HIVE_HOME ~/tooling/apache-hive-1.2.1-bin
set PATH $HADOOP_HOME/bin $PATH
set PATH $HIVE_HOME/bin $PATH

set GOPATH $HOME/go
set PATH $GOPATH/bin $PATH

set BEELINE_EP (pass hotstar/dp/hive/prod/hostname)
set BEELINE_USER (pass hotstar/dp/hive/prod/username)
set BEELINE_PWD (pass hotstar/dp/hive/prod/password)
