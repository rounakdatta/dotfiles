#!/usr/bin/env bash
set -euo pipefail

if [ ! -d "$HOME/personal/buku" ]; then
    git clone git@gitlab.com:rounakdatta/buku.git
    cp ~/personal/buku/bookmarks.db ~/.local/share/buku/bookmarks.db
fi

cp ~/.local/share/buku/bookmarks.db ~/personal/buku/
cd ~/personal/buku && (git add . && git commit -a -m "updates")
cd ~/personal/buku && git push origin master
