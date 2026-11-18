#!/bin/sh
# Runs `kanzo` with the container's arguments, after one first-run tweak.
#
# Kanzo's default config.toml says listen = "127.0.0.1", which inside a container means
# nobody outside it can reach the board. On the very first run only, create the config
# and switch it to 0.0.0.0. Later edits to /data/config.toml are left alone.
set -eu

config="${KANZO_HOME:-/data}/config.toml"
if [ ! -f "$config" ]; then
  kanzo init >/dev/null
  sed -i 's/^listen = "127.0.0.1"/listen = "0.0.0.0"/' "$config"
fi

exec kanzo "$@"
