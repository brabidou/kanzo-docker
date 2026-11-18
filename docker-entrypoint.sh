#!/bin/sh
# Runs `kanzo` with the container's arguments, after two first-run steps.
set -eu

# 1. As root (the default), make /data belong to PUID:PGID and drop to that user.
#    Hosts like Unraid hand the container a folder owned by root or nobody:users.
#    Started with --user instead, this is skipped and that user must own /data.
if [ "$(id -u)" = 0 ]; then
  if [ "$(stat -c %u:%g /data)" != "$PUID:$PGID" ]; then
    chown -R "$PUID:$PGID" /data
  fi
  exec su-exec "$PUID:$PGID" "$0" "$@"
fi

# 2. Kanzo's default config.toml says listen = "127.0.0.1", which inside a container means
#    nobody outside it can reach the board. On the very first run only, create the config
#    and switch it to 0.0.0.0. Later edits to /data/config.toml are left alone.
config="${KANZO_HOME:-/data}/config.toml"
if [ ! -f "$config" ]; then
  kanzo init >/dev/null
  sed -i 's/^listen = "127.0.0.1"/listen = "0.0.0.0"/' "$config"
fi

exec kanzo "$@"
