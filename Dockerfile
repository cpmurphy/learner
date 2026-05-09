# syntax = docker/dockerfile:1

# docker build -t chess-learner .
# docker run -d -p 3000:3000 --name chess-learner chess-learner

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.1
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
    apt-get install --no-install-recommends -y build-essential git wget pkg-config nodejs npm && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install gems
COPY Gemfile Gemfile.lock ./
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

# Build Stockfish
COPY Stockfish Stockfish
RUN cd Stockfish/src && \
    make clean && \
    make -j2 build ARCH=x86-64-avx2 && \
    strip stockfish && \
    mv stockfish /app/bin/ && \
    cd / && rm -rf Stockfish

# Final stage
FROM base

# Copy only necessary artifacts from build stage
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /app/bin/stockfish /app/bin/stockfish
COPY . /app
COPY --from=build /app/public/3rdparty-assets /app/public/3rdparty-assets
COPY --from=build /app/public/scripts/3rdparty /app/public/scripts/3rdparty
RUN rm -rf /app/Stockfish
RUN mkdir -p /app/games

# Set up non-root user
RUN groupadd --system --gid 1000 appgroup && \
    useradd appuser --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R appuser:appgroup /app
USER appuser

ENV PGN_DIR=/app/games
# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["bundle", "exec", "puma", "--port=3000"]
