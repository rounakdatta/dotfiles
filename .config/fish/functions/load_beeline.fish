function load_beeline
         set -xU BEELINE_EP (pass hotstar/dp/hive/prod/hostname)
         set -xU BEELINE_USER (pass hotstar/dp/hive/prod/username)
         set -xU BEELINE_PWD (pass hotstar/dp/hive/prod/password)
end

function beeline_hotstar
         jdk 1.8
         beeline -u jdbc:hive2://$BEELINE_EP -n $BEELINE_USER -p $BEELINE_PWD
end
