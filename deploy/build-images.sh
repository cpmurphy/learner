#!/usr/bin/env bash
# Builds both images from the repository root.
#
#   deploy/build-images.sh                    # x86-64-avx2 Stockfish build
#   STOCKFISH_ARCH=x86-64-sse41-popcnt deploy/build-images.sh   # CPUs without AVX2
set -euo pipefail

cd "$(dirname "$0")/.."
arch="${STOCKFISH_ARCH:-x86-64-avx2}"

if [ "$arch" = "x86-64-avx2" ] && ! grep -qw avx2 /proc/cpuinfo; then
  echo "This CPU has no AVX2; rerun with STOCKFISH_ARCH=x86-64-sse41-popcnt" >&2
  exit 1
fi

git submodule update --init Stockfish

podman build -f stockfish-pool/Containerfile --build-arg STOCKFISH_ARCH="$arch" -t localhost/stockfish-pool:latest .
podman build --target app -t localhost/chess-learner:app .

echo "Built localhost/stockfish-pool:latest and localhost/chess-learner:app"
