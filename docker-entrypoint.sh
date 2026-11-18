#!/bin/sh
# Starts Kanzo behind Caddy. Kanzo listens on 127.0.0.1:4241 inside the container and
# Caddy publishes it on port 4242 (see /etc/caddy/Caddyfile for why).
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

# 2. Only the default command starts the board. Anything else, like
#    `docker run ... kanzo export` or `--version`, runs on its own.
if [ "$*" != "--no-open" ]; then
  exec kanzo "$@"
fi

# 3. Kanzo's address belongs to the image: Caddy expects it at 127.0.0.1:4241. Set it on
#    every start, which also moves boards created by earlier images (0.0.0.0:4242) over.
#    Every other setting in config.toml stays as you left it.
config="${KANZO_HOME:-/data}/config.toml"
[ -f "$config" ] || kanzo init >/dev/null
sed -i -e 's/^port = .*/port = 4241/' -e 's/^listen = .*/listen = "127.0.0.1"/' "$config"

# 4. Caddy in the background, Kanzo as the main process: if Kanzo exits, the container
#    exits. The healthcheck goes through Caddy to Kanzo, so if Caddy dies the container
#    turns unhealthy.
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &

echo "kanzo-docker: the board is served on port 4242 (Kanzo's own 4241 is internal)."
exec kanzo --no-open
