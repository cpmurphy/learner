#!/usr/bin/env bash
# Checks that this host and user can run the deploy/quadlet units as intended.
# Run it as the user that will own the containers (not root, not via sudo),
# in a real login session (ssh in as that user; `su` lacks a systemd session).
#
# Prints PASS / WARN / FAIL per check and exits 1 if anything failed.
set -uo pipefail

# The checks below use `test && pass || fail`. That is safe here because pass,
# warn and fail always return 0, so the || branch runs only when the test fails.
# shellcheck disable=SC2015
failures=0
pass() { printf 'PASS  %s\n' "$1"; return 0; }
warn() { printf 'WARN  %s\n' "$1"; return 0; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); return 0; }
probe_image=docker.io/library/alpine:3.20

[ "$(id -u)" -ne 0 ] && pass "running as $(id -un), not root" || fail "run this as the deploy user, not root"

if ! command -v podman >/dev/null; then
  fail "podman is not installed"; exit 1
fi
version=$(podman version --format '{{.Client.Version}}')
if printf '4.4\n%s\n' "$version" | sort -V -C; then pass "podman $version (Quadlet needs 4.4+)"; else fail "podman $version is older than 4.4"; fi

[ "$(podman info --format '{{.Host.Security.Rootless}}')" = "true" ] && pass "podman is rootless" || fail "podman is not rootless"
backend=$(podman info --format '{{.Host.NetworkBackend}}')
[ "$backend" = "netavark" ] && pass "network backend netavark" || fail "network backend is $backend (need netavark)"

if ls /usr/lib/systemd/user-generators/podman-user-generator >/dev/null 2>&1; then
  pass "Quadlet user generator installed"
else
  fail "Quadlet user generator missing (/usr/lib/systemd/user-generators/podman-user-generator)"
fi

[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" = "yes" ] && pass "linger enabled (services survive logout and reboot)" \
  || fail "linger off: sudo loginctl enable-linger $(id -un)"

# Delegated cgroup controllers. (podman info's CgroupControllers can describe
# a different cgroup than the one containers run in, so read the real one.)
delegated=/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers
if [ -r "$delegated" ]; then
  for controller in cpu memory pids; do
    grep -qw "$controller" "$delegated" && pass "cgroup controller '$controller' delegated" \
      || fail "cgroup controller '$controller' not delegated (see deploy/README.md: cgroup delegation)"
  done
else
  fail "cannot read $delegated (cgroup v2 with systemd user sessions required)"
fi

# The limits actually applied inside a container.
if ! podman pull -q "$probe_image" >/dev/null 2>&1; then
  fail "cannot pull $probe_image for the container checks"; exit 1
fi
limits=$(podman run --rm --cpus=0.5 --memory=64m --pids-limit=32 "$probe_image" \
  sh -c 'cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/pids.max' 2>/dev/null | tr '\n' ' ')
case "$limits" in
  "50000 100000 67108864 32 ") pass "cpu, memory and pids limits are enforced in containers" ;;
  *) fail "container limits not enforced as expected (got: $limits)" ;;
esac

grep -qw avx2 /proc/cpuinfo && pass "CPU supports AVX2 (default Stockfish build)" \
  || warn "no AVX2: build with STOCKFISH_ARCH=x86-64-sse41-popcnt deploy/build-images.sh"

# The fixed subnets used by deploy/quadlet must be free.
used=$(podman network ls --format '{{.Name}} {{range .Subnets}}{{.Subnet}} {{end}}')
for subnet in 10.89.10.0/24 10.89.20.0/24; do
  owner=$(printf '%s\n' "$used" | grep -F "$subnet" | awk '{print $1}')
  if [ -z "$owner" ] || [ "$owner" = "sf-web" ] || [ "$owner" = "sf-engine" ]; then
    ip route | grep -qF "${subnet%/*}" && fail "$subnet is routed on this host; pick another subnet in deploy/quadlet" \
      || pass "subnet $subnet free"
  else
    fail "subnet $subnet already used by podman network '$owner'"
  fi
done

# An internal network must block outbound traffic.
probe_net=sf-check-$$
podman network create --internal "$probe_net" >/dev/null
if podman run --rm --network "$probe_net" "$probe_image" wget -T 3 -q -O /dev/null http://example.com 2>/dev/null; then
  fail "internal networks can reach the internet"
else
  pass "internal networks block outbound traffic"
fi
podman network rm "$probe_net" >/dev/null

if ss -ltn 2>/dev/null | grep -q '127.0.0.1:9292 '; then
  warn "127.0.0.1:9292 is already in use (fine if chess-learner is already running)"
else
  pass "port 127.0.0.1:9292 free"
fi

echo
[ "$failures" -eq 0 ] && echo "All required checks passed." || echo "$failures check(s) failed."
exit $((failures > 0))
