func setup_rclone
     bash -c 'sed -i -e "s/NAMESECRET/$(pass backblaze/name)/; s/ACCOUNTSECRET/$(pass backblaze/account)/; s/KEYSECRET/$(pass backblaze/key)/" ~/.config/rclone/rclone.conf'
end
