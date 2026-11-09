# Deploying chess-learner publicly (rootless Podman + Caddy)

This runs the app as two rootless Podman containers managed by systemd through
Quadlet, behind Caddy on the host:

```
internet ──TLS──> Caddy (host) ──> 127.0.0.1:9292 ──> chess-learner ──sf-engine──> stockfish-pool
                                    (sf-web network)     web app          (internal)   2 engines
```

- **chess-learner** (`localhost/chess-learner:app`): the web app, without Stockfish. It's published on `127.0.0.1:9292` only, its root filesystem is read-only, it has no capabilities, and it runs with memory and pids limits. It writes only to the library volume.
- **stockfish-pool** (`localhost/stockfish-pool:latest`): the engine service.
  - It's on an internal network only, with no published ports and no route to the internet.
  - Its root filesystem is read-only, it has no capabilities, and it runs as a non-root user inside a separate user namespace.
  - Its cpu, memory and pids are capped.
- **Rate limits, quotas and the owner login** are described in the main README ("Running It Publicly") and `stockfish-pool/README.md`.

Everything below runs as the user that will own the containers. Use a dedicated user if you can, logged in directly over ssh: `su` and `sudo -u` don't start the systemd user session these steps need.

## 1. Check the host

```bash
git clone --recurse-submodules <this repository> ~/chess-learner-src
cd ~/chess-learner-src
deploy/check-host.sh
```

Fix anything it reports as `FAIL`. The usual ones:

- **Linger:** run `sudo loginctl enable-linger <user>`. This keeps the services running after you log out and starts them at boot.
- **cgroup delegation:** this is needed for the cpu limit, and the memory and pids limits.

  ```bash
  sudo mkdir -p /etc/systemd/system/user@.service.d
  printf '[Service]\nDelegate=cpu cpuset io memory pids\n' | \
    sudo tee /etc/systemd/system/user@.service.d/delegate.conf
  sudo systemctl daemon-reload
  ```

  Then log out completely and back in, and run the check again.
- **Subnets already in use:** edit `Subnet=`/`Gateway=` in `deploy/quadlet/sf-*.network`, the app's `ip=` in `chess-learner.container`, and `TRUSTED_PROXIES` in step 3, all to match.

## 2. Build the images

```bash
deploy/build-images.sh                                  # CPUs with AVX2
STOCKFISH_ARCH=x86-64-sse41-popcnt deploy/build-images.sh   # CPUs without
```

This compiles Stockfish and `pgn2`'s Rust extension, so expect several minutes on a small VPS.

## 3. Configure

```bash
mkdir -p ~/.config/chess-learner ~/chess-learner/games
cp deploy/env/stockfish-pool.env.example ~/.config/chess-learner/stockfish-pool.env
cp deploy/env/chess-learner.env.example  ~/.config/chess-learner/chess-learner.env
chmod 600 ~/.config/chess-learner/*.env
```

Fill them in:

| Setting | Value |
|---|---|
| `API_TOKENS` (stockfish-pool) and `ENGINE_TOKEN` (chess-learner) | The same value, from `openssl rand -hex 32` |
| `OWNER_PASSWORD_HASH` | The line printed by `bin/owner-password` (needs Ruby; or run `podman run --rm -it localhost/chess-learner:app bin/owner-password`) |
| `ENGINE_SUBJECT_SECRET`, `SESSION_SECRET` | Each from `openssl rand -hex 64` |
| `TRUSTED_PROXIES` | Leave at `10.89.10.2`: rootless Podman delivers connections to the published port from the app container's own address, which the unit pins. Change it only if step 6 says otherwise |

Write values without quotes. Podman passes everything after `=` literally, `$` signs included.

Put your PGN files in `~/chess-learner/games`. Uploads and saves from the owner login also land there.

## 4. Install and start the services

```bash
mkdir -p ~/.config/containers/systemd
cp deploy/quadlet/* ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start stockfish-pool chess-learner
systemctl --user status stockfish-pool chess-learner
```

Quadlet generates `stockfish-pool.service`, `chess-learner.service`, `sf-engine-network.service` and `sf-web-network.service`. They start at boot because of linger and `WantedBy=default.target`. A container that crashes, or fails its health check three times in a row, is restarted.

## 5. Point Caddy at it

Add `deploy/caddy/chess-learner.caddy` (with your hostname) to your Caddyfile, then run `sudo systemctl reload caddy`.

## 6. Verify

```bash
curl -s http://127.0.0.1:9292/api/session            # {"owner":false,"login_enabled":true}
podman healthcheck run stockfish-pool && echo engine healthy
podman healthcheck run chess-learner && echo app healthy
journalctl --user -u chess-learner -n 50 | grep -i TRUSTED_PROXIES
```

If the last command prints a warning such as `Request from 10.89.10.3 carries X-Forwarded-For, but 10.89.10.3 is not in TRUSTED_PROXIES`, put that address in `TRUSTED_PROXIES`. Then run `systemctl --user restart chess-learner`. Until that's done, every visitor shares one rate limit.

Then open the site, log in at `/login` and load a game.

## Updating

```bash
cd ~/chess-learner-src && git pull --recurse-submodules
deploy/build-images.sh
cp deploy/quadlet/* ~/.config/containers/systemd/ && systemctl --user daemon-reload
systemctl --user restart stockfish-pool chess-learner
```

## Logs and troubleshooting

- `journalctl --user -u stockfish-pool -f` shows engine restarts (`worker N failed`) and start failures.
  - If every worker fails at start with "illegal instruction", Stockfish was built for the wrong CPU; see step 2.
- `curl` can't reach `/healthz` from the host, because the engine has no published port. Use `podman exec chess-learner ruby -rnet/http -e 'puts Net::HTTP.get(URI("http://stockfish-pool:4000/healthz"))'`.
- `systemctl --user stop chess-learner stockfish-pool` stops everything. Removing the files from `~/.config/containers/systemd/` and running `daemon-reload` uninstalls it.
