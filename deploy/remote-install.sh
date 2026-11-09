#!/usr/bin/env bash
# Installs a release on the server: run as the deploy user (bin/deploy.sh does
# this over ssh). It
#   1. on the first install, checks the host (deploy/check-host.sh);
#   2. loads the new images;
#   3. creates the env files with generated secrets if they do not exist
#      (existing env files are never changed);
#   4. installs the Quadlet units and restarts both services;
#   5. waits until both report healthy, then remembers the release as :good
#      (and the good release before it as :previous).
#
#   deploy/remote-install.sh <images.tar.gz>   install a release
#   deploy/remote-install.sh --rollback        go back to the last good release:
#       :good if the running images never passed their health checks,
#       otherwise :previous (the good release before the running one); rolling
#       back twice in a row returns to where you started
#
# Environment: FRONTEND_NAME / BACKEND_NAME (service names, default
# chess-learner / stockfish-pool), STOCKFISH_ARCH (what the engine was built
# for), SKIP_HOST_CHECK=1, RELEASE (a label for messages).
set -euo pipefail

release_dir=$(cd "$(dirname "$0")/.." && pwd)
frontend=${FRONTEND_NAME:-chess-learner}
backend=${BACKEND_NAME:-stockfish-pool}
release=${RELEASE:-unknown}
images=(localhost/chess-learner:app localhost/stockfish-pool:latest)

# Commands, overridable so the script can be exercised without a server.
podman_cmd=${PODMAN:-podman}
systemctl_cmd=${SYSTEMCTL:-systemctl --user}
health_attempts=${HEALTH_ATTEMPTS:-60}

config_dir=$HOME/.config/chess-learner
unit_dir=$HOME/.config/containers/systemd
games_dir=$HOME/chess-learner/games

# systemctl --user needs the user's runtime directory; non-interactive ssh
# sessions do not always set it.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

step() { printf '\n==> %s\n' "$1"; }
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

for name in "$frontend" "$backend"; do
  [ -f "$release_dir/deploy/quadlet/$name.container" ] ||
    die "no deploy/quadlet/$name.container; FRONTEND_NAME/BACKEND_NAME must match the unit file names"
done

wait_healthy() {
  local container=$1 attempt
  for attempt in $(seq 1 "$health_attempts"); do
    $podman_cmd healthcheck run "$container" >/dev/null 2>&1 && return 0
    [ "$attempt" -lt "$health_attempts" ] && sleep 2
  done
  return 1
}

restart_and_wait() {
  step "Restarting $backend and $frontend"
  $systemctl_cmd daemon-reload
  # shellcheck disable=SC2086 # $systemctl_cmd is a command plus its options
  $systemctl_cmd restart "$backend.service" "$frontend.service"

  step "Waiting for both services to report healthy"
  local container
  for container in "$backend" "$frontend"; do
    if wait_healthy "$container"; then
      echo "$container: healthy"
    else
      echo "$container did not become healthy. Recent log:" >&2
      $podman_cmd logs --tail 30 "$container" >&2 || true
      echo "To go back to the previous release: deploy/remote-install.sh --rollback" >&2
      exit 1
    fi
  done
}

image_id() { $podman_cmd image inspect --format '{{.Id}}' "$1" 2>/dev/null || true; }

# After a release passes its health checks: the old :good becomes :previous.
remember_good_release() {
  local image good current
  for image in "${images[@]}"; do
    good=$(image_id "${image%:*}:good")
    current=$(image_id "$image")
    if [ -n "$good" ] && [ "$good" != "$current" ]; then
      $podman_cmd tag "${image%:*}:good" "${image%:*}:previous"
    fi
    $podman_cmd tag "$image" "${image%:*}:good"
  done
}

if [ "${1:-}" = "--rollback" ]; then
  # Healthy running release: go to the one before it. Broken one: go to :good.
  target=previous
  for image in "${images[@]}"; do
    [ "$(image_id "$image")" = "$(image_id "${image%:*}:good")" ] || target=good
  done
  step "Rolling back to the :$target images"
  for image in "${images[@]}"; do
    $podman_cmd image exists "${image%:*}:$target" || die "no ${image%:*}:$target image to roll back to"
  done
  for image in "${images[@]}"; do
    $podman_cmd tag "${image%:*}:$target" "$image"
  done
  restart_and_wait
  [ "$target" = previous ] && remember_good_release
  echo
  echo "Rolled back to the :$target release."
  exit 0
fi

archive=${1:?usage: deploy/remote-install.sh <images.tar.gz> | --rollback}
[ -f "$archive" ] || die "image archive $archive not found"

if [ "${STOCKFISH_ARCH:-x86-64-avx2}" = "x86-64-avx2" ] && ! grep -qw avx2 /proc/cpuinfo; then
  die "this CPU has no AVX2 but the engine was built for x86-64-avx2; set STOCKFISH_ARCH=x86-64-sse41-popcnt in deploy_env.sh"
fi

if [ ! -f "$unit_dir/$frontend.container" ] && [ "${SKIP_HOST_CHECK:-}" != 1 ]; then
  step "First install: checking the host"
  "$release_dir/deploy/check-host.sh" || die "fix the failed checks above (see deploy/README.md), then deploy again"
fi

step "Loading images for release $release"
$podman_cmd load -i "$archive"

step "Configuration"
mkdir -p "$config_dir" "$games_dir" "$unit_dir"
chmod 700 "$config_dir"
pool_env=$config_dir/stockfish-pool.env
app_env=$config_dir/chess-learner.env

random_hex() { # $1 bytes of randomness as hex
  openssl rand -hex "$1" 2>/dev/null || od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'
}

if [ ! -f "$pool_env" ] && [ ! -f "$app_env" ]; then
  token=$(random_hex 32)
  umask 077
  sed "s/^API_TOKENS=\$/API_TOKENS=$token/" "$release_dir/deploy/env/stockfish-pool.env.example" > "$pool_env"
  sed -e "s/^ENGINE_TOKEN=\$/ENGINE_TOKEN=$token/" \
      -e "s/^ENGINE_SUBJECT_SECRET=\$/ENGINE_SUBJECT_SECRET=$(random_hex 64)/" \
      -e "s/^SESSION_SECRET=\$/SESSION_SECRET=$(random_hex 64)/" \
      "$release_dir/deploy/env/chess-learner.env.example" > "$app_env"
  umask 022
  echo "Created $pool_env and $app_env with generated secrets."
elif [ ! -f "$pool_env" ] || [ ! -f "$app_env" ]; then
  die "only one of $pool_env and $app_env exists; their tokens must match, so create the other by hand (deploy/README.md, step 3)"
else
  echo "Keeping the existing env files in $config_dir."
fi
if ! grep -qE '^OWNER_PASSWORD_HASH=.+' "$app_env"; then
  echo "NOTE: OWNER_PASSWORD_HASH is not set, so nobody can upload or save. To enable the owner login:"
  echo "      podman run --rm -it localhost/chess-learner:app bin/owner-password"
  echo "      then put the printed line after OWNER_PASSWORD_HASH= in $app_env and deploy again"
  echo "      (or: systemctl --user restart $frontend)."
fi

step "Installing Quadlet units"
for unit in "$release_dir"/deploy/quadlet/*; do
  target=$unit_dir/$(basename "$unit")
  if cmp -s "$unit" "$target"; then
    echo "unchanged: $(basename "$unit")"
  else
    install -m 0644 "$unit" "$target"
    echo "installed: $(basename "$unit")"
  fi
done

restart_and_wait
remember_good_release

step "Cleaning up"
rm -f "$archive"
$podman_cmd image prune -f >/dev/null # dangling images only; other apps' images and containers are left alone
echo
echo "Release $release is running."
