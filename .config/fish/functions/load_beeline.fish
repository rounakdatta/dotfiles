function load_beeline
         set -xU BEELINE_EP (pass hotstar/dp/hive/prod/hostname)
         set -xU BEELINE_USER (pass hotstar/dp/hive/prod/username)
         set -xU BEELINE_PWD (pass hotstar/dp/hive/prod/password)
end
