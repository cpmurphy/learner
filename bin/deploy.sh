#!/usr/bin/env bash
# Deploys the complete application (web app + stockfish-pool engine service)
# to the server named in deploy_env.sh:
#
#   1. refuses to run with uncommitted changes to tracked files;
#   2. runs the tests and lint (SKIP_TESTS=1 skips them);
#   3. builds both images here (deploy/build-images.sh);
#   4. copies them, with deploy/, to the server;
#   5. runs deploy/remote-install.sh there, which installs and restarts the
#      services and waits until they are healthy;
#   6. checks the public URL through Caddy.
#
#   bin/deploy.sh               deploy the current commit
#   bin/deploy.sh --build-only  steps 1-3 plus the image archive, no server access
#   bin/deploy.sh --rollback    switch the server back to the last good release
#
# deploy_env.sh (repository root, not committed; see deploy/deploy_env.sh.example)
# sets DEPLOY_USER, DEPLOY_HOST, DEPLOY_DIR and optionally FRONTEND_NAME,
# BACKEND_NAME, PUBLIC_URL and STOCKFISH_ARCH.
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f deploy_env.sh ] || { echo "deploy_env.sh not found; copy deploy/deploy_env.sh.example" >&2; exit 1; }
# shellcheck source=/dev/null
. ./deploy_env.sh

: "${DEPLOY_USER:?set DEPLOY_USER in deploy_env.sh}"
: "${DEPLOY_HOST:?set DEPLOY_HOST in deploy_env.sh}"
: "${DEPLOY_DIR:?set DEPLOY_DIR in deploy_env.sh}"
FRONTEND_NAME=${FRONTEND_NAME:-chess-learner}
BACKEND_NAME=${BACKEND_NAME:-stockfish-pool}
STOCKFISH_ARCH=${STOCKFISH_ARCH:-x86-64-avx2}
PUBLIC_URL=${PUBLIC_URL:-}

mode=${1:-deploy}
remote="${DEPLOY_USER}@${DEPLOY_HOST}"
remote_release_dir="${DEPLOY_DIR}/${FRONTEND_NAME}-release"
remote_env="FRONTEND_NAME=$FRONTEND_NAME BACKEND_NAME=$BACKEND_NAME STOCKFISH_ARCH=$STOCKFISH_ARCH"

step() { printf '\n==> %s\n' "$1"; }

case "$mode" in
  deploy | --build-only) ;;
  --rollback)
    step "Rolling back on $DEPLOY_HOST"
    # shellcheck disable=SC2029 # $remote_env and the path are meant to expand here
    ssh "$remote" "cd '$remote_release_dir' && $remote_env deploy/remote-install.sh --rollback"
    exit 0
    ;;
  *) echo "usage: bin/deploy.sh [--build-only | --rollback]" >&2; exit 2 ;;
esac

step "Checking the working tree"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Uncommitted changes to tracked files; commit or stash them first." >&2
  exit 1
fi
revision=$(git rev-parse --short HEAD)
echo "Deploying commit $revision ($(git log -1 --format=%s))"

if [ "${SKIP_TESTS:-}" != 1 ]; then
  step "Running tests and lint"
  bundle exec rake test
  (cd stockfish-pool && bundle exec rake test)
  bin/rubocop
fi

step "Building images for Stockfish ARCH=$STOCKFISH_ARCH"
STOCKFISH_ARCH="$STOCKFISH_ARCH" deploy/build-images.sh

step "Saving images"
archive_dir=$(mktemp -d)
trap 'rm -rf "$archive_dir"' EXIT
archive="$archive_dir/images-$revision.tar.gz"
podman save -m localhost/chess-learner:app localhost/stockfish-pool:latest | gzip > "$archive"
echo "$(du -h "$archive" | cut -f1) $archive"

if [ "$mode" = --build-only ]; then
  cp "$archive" .
  echo
  echo "Built release $revision: ./$(basename "$archive") (not deployed)."
  exit 0
fi

step "Uploading release $revision to $DEPLOY_HOST:$remote_release_dir"
# shellcheck disable=SC2029 # the path is meant to expand here
ssh "$remote" "mkdir -p '$remote_release_dir'"
rsync -a --delete deploy "$remote:$remote_release_dir/"
rsync -a --partial --progress "$archive" "$remote:$remote_release_dir/"

step "Installing on $DEPLOY_HOST"
# shellcheck disable=SC2029 # meant to expand here
ssh "$remote" "cd '$remote_release_dir' && RELEASE=$revision $remote_env deploy/remote-install.sh '$(basename "$archive")'"

if [ -n "$PUBLIC_URL" ]; then
  step "Checking $PUBLIC_URL through Caddy"
  if session=$(curl -fsS --max-time 15 "$PUBLIC_URL/api/session"); then
    echo "$PUBLIC_URL/api/session: $session"
  else
    echo "WARNING: $PUBLIC_URL/api/session did not answer. Is Caddy proxying to 127.0.0.1:9292?" >&2
    exit 1
  fi
  # That request came through Caddy, so a wrong TRUSTED_PROXIES shows up now.
  # shellcheck disable=SC2029
  if ssh "$remote" "podman logs --since 2m '$FRONTEND_NAME' 2>&1 | grep 'carries X-Forwarded-For'"; then
    echo "WARNING: put the address above in TRUSTED_PROXIES (~/.config/chess-learner/chess-learner.env on the server)" >&2
    echo "         and restart: ssh $remote systemctl --user restart $FRONTEND_NAME" >&2
    exit 1
  fi
  echo "TRUSTED_PROXIES is right: no untrusted-proxy warning."
fi

echo
echo "Deployed $revision to $DEPLOY_HOST."
