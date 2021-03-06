if [ -n "$TMUX_PANE" ]
  set HISTFILE $HOME/.local/share/fish/fish_history_tmux_$TMUX_PANE
end


set HADOOP_HOME ~/tooling/hadoop-2.5.1
set HIVE_HOME ~/tooling/apache-hive-1.2.1-bin
set CONFLUENT_HOME ~/tooling/confluent-6.0.0
set MVN_HOME ~/tooling/apache-maven-3.6.3
set PATH $HADOOP_HOME/bin $PATH
set PATH $HIVE_HOME/bin $PATH
set PATH $CONFLUENT_HOME/bin $PATH
set PATH $MVN_HOME/bin $PATH

# librdkafka, project-specific
set OPENSSL_HOME /usr/local/opt/openssl@1.1/lib/pkgconfig/
set PKG_CONFIG_PATH $OPENSSL_HOME $PKG_CONFIG_PATH

set GOPATH $HOME/go
set PATH $GOPATH/bin $PATH
