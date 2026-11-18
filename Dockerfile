# Kanzo in a container: https://github.com/emanuele-em/kanzo
#
# This image packages the official, prebuilt static (musl) release binary rather than
# compiling from source, so it is byte-for-byte the program upstream ships, and a
# multi-arch build takes seconds instead of a cross-compile per platform.

ARG ALPINE_VERSION=3.22

# ---- fetch: download and verify the release binary for the target platform ----
FROM alpine:${ALPINE_VERSION} AS fetch

# The Kanzo release to package, without the leading "v". CI passes the latest one.
ARG KANZO_VERSION=0.4.2
# Set by `docker buildx` for each platform being built.
ARG TARGETARCH
ARG TARGETVARIANT

RUN apk add --no-cache curl xz

WORKDIR /tmp/kanzo
RUN set -eu; \
    case "${TARGETARCH}${TARGETVARIANT:+/$TARGETVARIANT}" in \
      amd64)  target=x86_64-unknown-linux-musl ;; \
      arm64)  target=aarch64-unknown-linux-musl ;; \
      arm/v7) target=armv7-unknown-linux-musleabihf ;; \
      arm/v6) target=arm-unknown-linux-musleabihf ;; \
      *) echo "Kanzo has no release for ${TARGETARCH}${TARGETVARIANT:+/$TARGETVARIANT}" >&2; exit 1 ;; \
    esac; \
    base="https://github.com/emanuele-em/kanzo/releases/download/v${KANZO_VERSION}"; \
    curl -fsSLO "${base}/kanzo-${target}.tar.xz"; \
    curl -fsSLO "${base}/kanzo-${target}.tar.xz.sha256"; \
    # Upstream's .sha256 is "<hash> *<file>"; rewrite it into the form busybox sha256sum checks.
    echo "$(cut -d' ' -f1 "kanzo-${target}.tar.xz.sha256")  kanzo-${target}.tar.xz" | sha256sum -c -; \
    tar -xJf "kanzo-${target}.tar.xz" --strip-components=1; \
    ./kanzo --version

# ---- runtime ----
FROM alpine:${ALPINE_VERSION}

ARG KANZO_VERSION=0.4.2

LABEL org.opencontainers.image.title="kanzo" \
      org.opencontainers.image.description="Kanzo, the kanban board and MCP server for humans and agents, in a container" \
      org.opencontainers.image.version="${KANZO_VERSION}" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.url="https://github.com/emanuele-em/kanzo"

# git: `kanzo sync` and the project lookup shell out to it.
# ca-certificates: so git can reach https remotes.
# No curl on purpose: without it Kanzo's self-updater stays quiet, because a container is
# updated by pulling a new image, not by replacing the binary inside it.
RUN apk add --no-cache git ca-certificates \
 && adduser -D -u 1000 -h /data kanzo

COPY --from=fetch /tmp/kanzo/kanzo /usr/local/bin/kanzo
COPY --from=fetch /tmp/kanzo/LICENSE /usr/share/licenses/kanzo/LICENSE
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# The whole board lives here: kanzo.db, images and config.toml.
ENV KANZO_HOME=/data
VOLUME /data
WORKDIR /data
USER kanzo

EXPOSE 4242

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4242/api/ping >/dev/null || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["--no-open"]
