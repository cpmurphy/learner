# deploy/

`deploy/` holds the public deployment: Quadlet units for rootless Podman (`deploy/quadlet/`), env-file templates, a Caddy site block, `build-images.sh`, `check-host.sh` and `remote-install.sh`. Its guide is `deploy/README.md`.
- `bin/deploy.sh` deploys from a workstation: it builds the images, ships them with `deploy/` over ssh, and runs `deploy/remote-install.sh` on the server, with rollback via `:good`/`:previous` image tags. Its settings are in the gitignored `deploy_env.sh` (template: `deploy/deploy_env.sh.example`).
- `test/remote_install_test.rb` exercises `remote-install.sh` against the fake `podman`/`systemctl` in `test/support/deploy/`.
- **Images:** the `Dockerfile` has two targets. `app` has no Stockfish and is used with `ENGINE_URL`; `standalone` is the default and includes Stockfish. `stockfish-pool/Containerfile` is built from the repository root.
- **TRUSTED_PROXIES:** rootless Podman delivers connections to a published port from the container's *own* address. That's why the app has a fixed IP on `sf-web` (10.89.10.2) and `TRUSTED_PROXIES` names it.
