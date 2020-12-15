#!/usr/bin/env bash
set -euo pipefail

bash -c 'rclone sync -i ~/files $(pass backblaze/name):$(pass backblaze/bucket) --exclude ".DS_Store"'
