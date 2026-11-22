#!/usr/bin/env bash
# Builds both images from the repository root.
#
#   deploy/build-images.sh                    # x86-64-avx2 Stockfish build
#   STOCKFISH_ARCH=x86-64-sse41-popcnt deploy/build-images.sh   # CPUs without AVX2
#
# The pool image is built from the stockfish-pool checkout at POOL_REF (see
# bin/pool-checkout). Stockfish must suit the CPU it will RUN on. Without
# STOCKFISH_ARCH this checks the local CPU; when building for another machine
# (bin/deploy.sh does), set STOCKFISH_ARCH for that machine and the local
# check is skipped.
set -euo pipefail

cd "$(dirname "$0")/.."
arch="${STOCKFISH_ARCH:-x86-64-avx2}"

if [ -z "${STOCKFISH_ARCH:-}" ] && ! grep -qw avx2 /proc/cpuinfo; then
  echo "This CPU has no AVX2; rerun with STOCKFISH_ARCH=x86-64-sse41-popcnt" >&2
  exit 1
fi

bin/check-pool-ref
pool=$(bin/pool-checkout)
ref=$(tr -d '[:space:]' <POOL_REF)
echo "Building stockfish-pool from $pool ($ref)"
STOCKFISH_ARCH="$arch" "$pool/deploy/build-image.sh"

podman build --target app -t localhost/chess-learner:app .

echo "Built localhost/stockfish-pool:latest and localhost/chess-learner:app"
