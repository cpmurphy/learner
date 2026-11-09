# syntax = docker/dockerfile:1

# Two images can be built from this file:
#
#   docker build -t chess-learner .                  # "standalone" (default): includes Stockfish
#   docker build --target app -t chess-learner:app . # no Stockfish; set ENGINE_URL to use the
#                                                    # stockfish-pool service (see deploy/)
#
# docker run -d -p 3000:3000 --name chess-learner chess-learner

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.12
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /app

# Install only essential packages
RUN mkdir -p /app/bin && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV APP_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    PATH="$PATH:/app/bin" \
    RAILS_LOG_TO_STDOUT="1"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install build dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git wget pkg-config libclang-dev nodejs npm && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install gems
COPY Gemfile Gemfile.lock ./
# Path gem referenced by the Gemfile; it must be present before bundle install.
COPY stockfish-pool/client stockfish-pool/client
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy browser dependencies into public/ so the final image can serve them as static assets.
COPY package.json package-lock.json ./
RUN npm ci && \
    npm run copy-all && \
    test -f public/3rdparty-assets/cm-chessboard/extensions/arrows/arrows.css && \
    test -f public/scripts/3rdparty/cm-chessboard/Chessboard.js && \
    npm cache clean --force && \
    rm -rf node_modules

# Stockfish, for the standalone image only (--target app skips this stage).
# x86-64-avx2 needs a CPU with AVX2 (check: grep -c avx2 /proc/cpuinfo);
# otherwise pass --build-arg STOCKFISH_ARCH=x86-64-sse41-popcnt.
FROM build AS stockfish
ARG STOCKFISH_ARCH=x86-64-avx2
COPY Stockfish Stockfish
RUN cd Stockfish/src && \
    make clean && \
    make -j"$(nproc)" build ARCH="${STOCKFISH_ARCH}" && \
    strip stockfish && \
    mv stockfish /app/bin/

# The web app without an engine. Code is owned by root and only readable by
# the app user, so a compromised app cannot rewrite itself; the app writes only
# to PGN_DIR (/app/games, normally a volume) and /tmp.
FROM base AS app

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY . /app
COPY --from=build /app/public/3rdparty-assets /app/public/3rdparty-assets
COPY --from=build /app/public/scripts/3rdparty /app/public/scripts/3rdparty
# The engine service's server code is not part of this image; its client gem is.
RUN rm -rf /app/Stockfish /app/stockfish-pool/lib /app/stockfish-pool/test /app/stockfish-pool/config \
           /app/stockfish-pool/config.ru /app/test /app/coverage /app/sandbox && \
    groupadd --system --gid 1000 appgroup && \
    useradd appuser --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /app/games && chown appuser:appgroup /app/games && \
    chmod -R a+rX,go-w /app
USER appuser

ENV PGN_DIR=/app/games
EXPOSE 3000
CMD ["bundle", "exec", "puma", "--port=3000"]

# Default image: the app plus a local Stockfish, for single-user local use
# (docker-compose.yml, podman-start.sh). Everyone who can reach it may upload
# and save, as before, and cookies work over plain http. Setting
# OWNER_PASSWORD_HASH still switches on the owner login.
FROM app AS standalone
COPY --from=stockfish /app/bin/stockfish /app/bin/stockfish
ENV OWNER_ACCESS="open" \
    COOKIE_SECURE="false"
