# kanzo-docker

[Kanzo](https://github.com/emanuele-em/kanzo) in a container. Kanzo is a kanban board and MCP server for you and your coding agents. This repo packages it as a small, multi-arch Docker image, and rebuilds the image on its own when upstream publishes a new release.

> This is an unofficial community image. Bugs in Kanzo itself belong [upstream](https://github.com/emanuele-em/kanzo/issues). Bugs in the image belong here.

- **Image:** `ghcr.io/brabidou/kanzo`
- **Platforms:** `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/arm/v6` (that covers every Raspberry Pi)
- **Contents:** the official, checksum-verified release binary on Alpine, plus `git` for `kanzo sync`. It runs as a non-root user (uid 1000).

## Quick start

```sh
docker run -d --name kanzo --restart unless-stopped \
  -p 4242:4242 -v kanzo-data:/data \
  ghcr.io/brabidou/kanzo:latest
```

Then open http://localhost:4242.

With Compose, using the [`compose.yaml`](compose.yaml) in this repo:

```sh
docker compose up -d
```

> [!IMPORTANT]
> **The host port and the container port must match** (`-p 4242:4242`, not `-p 8080:4242`). Kanzo turns away any request whose `Host` header names a port other than its own, which protects it against DNS rebinding. To use another port, see [Change the port](#change-the-port).

> [!WARNING]
> **Kanzo has no logins.** Anyone who can reach the port can read and change the board and use its MCP endpoint. Expose it only on a network you trust: your machine, your LAN, or a VPN like Tailscale.

## Connect your agents

Kanzo serves MCP over HTTP at `/mcp`:

```sh
claude mcp add --transport http kanzo --scope user http://localhost:4242/mcp   # Claude Code
```

For other clients, point them at `http://localhost:4242/mcp`.

Over HTTP, Kanzo can't see which repo the agent is working in, so agents have to name the project (`project: "api"`). Upstream's automatic match from the git remote needs `kanzo mcp` to run on the same machine as the repo.

## Data

Everything is stored in `/data`: the board in `kanzo.db`, pasted images, and `config.toml`. Keep that directory on a volume, or you lose the board when the container is removed.

**Bind mount instead of a named volume:** the directory has to be writable by uid 1000. You can also run the container as yourself:

```sh
mkdir -p ./kanzo-data
docker run -d --name kanzo -p 4242:4242 -v "$PWD/kanzo-data:/data" \
  --user "$(id -u):$(id -g)" ghcr.io/brabidou/kanzo:latest
```

**Backup:** export the board while it runs, or stop the container and copy the volume:

```sh
docker exec kanzo kanzo export -f json > kanzo-backup.json
```

## Configuration

On first start, the entrypoint creates `/data/config.toml` with `listen = "0.0.0.0"`. Kanzo's own default is `127.0.0.1`, which can't be reached from outside a container. After that the file belongs to you, and the entrypoint never touches it again:

```sh
docker exec -it kanzo vi /data/config.toml
docker restart kanzo
```

The upstream [Settings](https://github.com/emanuele-em/kanzo#settings) section describes every key.

### Change the port

Change all three places together: the `-p` mapping, `port` in `config.toml`, and the healthcheck, which probes 4242. For example, for 4300:

```sh
docker run -d --name kanzo -p 4300:4300 -v kanzo-data:/data \
  --health-cmd 'wget -qO- http://127.0.0.1:4300/api/ping' \
  ghcr.io/brabidou/kanzo:latest --no-open --port 4300
```

Instead of `--port`, you can set `port = 4300` in `config.toml`.

### Behind a reverse proxy

Kanzo accepts a `Host` only if it is `localhost`, an IP address, or the machine's own hostname. It also requires a request's `Origin` to be `http://<that host>`. A proxy serving a domain over HTTPS therefore has to rewrite both. With nginx:

```nginx
location / {
    proxy_pass http://127.0.0.1:4242;
    proxy_set_header Host localhost:4242;
    proxy_set_header Origin http://localhost:4242;
    proxy_http_version 1.1;
    proxy_buffering off;   # the board and MCP stream updates
}
```

Put authentication on the proxy. Kanzo has none.

## Commands

Every `kanzo` command runs inside the container:

```sh
docker exec kanzo kanzo --version
docker exec kanzo kanzo export          # the board as Markdown
docker exec kanzo kanzo sync            # see below
```

Arguments passed to `docker run` go to `kanzo` (the default is `--no-open`).

These native commands don't apply in a container: `kanzo service install` (Docker's `--restart` does that job), `kanzo update` (pull a new image), and `kanzo share on|off` (the container's board is always shared on the network it can reach).

### Sync with git

`kanzo sync` works if the container can authenticate to the remote. The image doesn't include SSH, so use an HTTPS URL with a token that has access to just that one private repo:

```sh
docker exec kanzo kanzo sync --repo https://<user>:<token>@github.com/<user>/kanzo-data
```

The token ends up in `/data/.git/config`, so treat the volume as a secret.

## Updating

```sh
docker compose pull && docker compose up -d
# or
docker pull ghcr.io/brabidou/kanzo:latest && docker rm -f kanzo && docker run ...   # same flags as before
```

The board is kept on the volume, and Kanzo migrates its database on start. The image ships without `curl`, so the board won't offer to update itself.

### Tags

| Tag | Points to |
| --- | --- |
| `latest` | the newest Kanzo release |
| `0.4.2` | exactly that release |
| `0.4` | the newest `0.4.x` |

## How the image is built automatically

[`.github/workflows/docker.yml`](.github/workflows/docker.yml) builds and publishes the image:

1. **Every 6 hours** it reads the latest release of `emanuele-em/kanzo`. When `ghcr.io` doesn't have that version yet, it builds and pushes it. A new upstream release is therefore published here within about 6 hours.
2. **On a push to `main`** that changes the Dockerfile, the entrypoint or the workflow, it rebuilds the current release, so image fixes ship right away.
3. **On a pull request** it builds and tests, but doesn't push.
4. **By hand:** Actions → docker → Run workflow. Optionally give it a version to (re)build. An older version never moves `latest`.

Before anything is published, each build starts the amd64 image and checks that `/api/ping` answers. Then it builds all four platforms and pushes them under one multi-arch tag.

Why polling: a webhook would have to be added to the upstream repo, which we don't control. The release binaries come from upstream's own CI and are verified against its published SHA-256 checksums. That keeps the image identical to what upstream ships, so builds don't need to cross-compile Rust.

Maintainer notes:

- GitHub **turns off scheduled workflows after 60 days without activity** in a public repo. If new releases stop showing up, re-enable the workflow on the Actions tab.
- The first push creates the `kanzo` package under your account. If it shows as private, make it public under *Package settings → Change visibility*.

## Build it yourself

```sh
docker build -t kanzo .                                   # the version pinned in the Dockerfile
docker build --build-arg KANZO_VERSION=0.4.2 -t kanzo .   # a specific release
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7,linux/arm/v6 -t kanzo .
```

## Files

| File | What it is |
| --- | --- |
| [`Dockerfile`](Dockerfile) | Downloads and verifies the release binary, then builds the Alpine runtime image |
| [`docker-entrypoint.sh`](docker-entrypoint.sh) | Sets `listen = "0.0.0.0"` on first start, then runs `kanzo` |
| [`compose.yaml`](compose.yaml) | Compose setup with a named volume |
| [`.github/workflows/docker.yml`](.github/workflows/docker.yml) | Release watcher, test and multi-arch publish |

## License

Kanzo is licensed under [AGPL-3.0](https://github.com/emanuele-em/kanzo/blob/main/LICENSE), and its license is included in the image at `/usr/share/licenses/kanzo/LICENSE`. The image contains Kanzo unmodified. The packaging files in this repo are separate from Kanzo.
