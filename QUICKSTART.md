# Quick Start Guide

The quickest way to run Chess Learner is in a container with
[Podman](https://podman.io). The image includes Stockfish, so you don't need
Ruby, Node.js or a chess engine on your machine. To run it natively instead, see
the [full installation instructions](INSTALL.md).

This guide is for running it for yourself, on your own computer. To put it on a
public server, see [deploy/README.md](deploy/README.md).

## 1. Get the code

```bash
git clone --recurse-submodules <this repository> chess-learner
cd chess-learner
```

If you already cloned it without `--recurse-submodules`, run
`git submodule update --init Stockfish`.

## 2. Install Podman

- **Linux:** `sudo apt-get install podman` (Ubuntu/Debian),
  `sudo dnf install podman` (Fedora) or `sudo pacman -S podman` (Arch).
  Podman 4.4 or later is needed for Quadlet.
- **Mac and Windows:** containers are Linux programs, so Podman runs them in a
  small Linux virtual machine, the *Podman machine*. Install
  [Podman Desktop](https://podman-desktop.io) and follow its setup, which
  creates and starts the machine (on Windows it installs WSL 2 first if you
  don't have it). Podman Desktop also installs the `podman` command, which the
  steps below use.

## 3. Build the image

From the `chess-learner` folder (on Mac and Windows, in Terminal or PowerShell):

```bash
podman build -t localhost/chess-learner:standalone .
```

This compiles Stockfish, so the first build takes several minutes. It builds
for x86 CPUs with AVX2, which covers most PCs and Intel Macs from the last ten
years. Otherwise add a build argument:

| Computer | Add |
|---|---|
| Mac with Apple Silicon (M1 and later), or another ARM machine | `--build-arg STOCKFISH_ARCH=armv8` |
| Older x86 CPU without AVX2 | `--build-arg STOCKFISH_ARCH=x86-64-sse41-popcnt` |

## 4. Run it

- [Linux](#linux-as-a-systemd-service-quadlet)
- [Mac](#mac)
- [Windows](#windows)

### Linux: as a systemd service (Quadlet)

[Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
lets systemd run the container like any other service: it starts when you log
in and restarts if it crashes.

```bash
mkdir -p ~/chess-learner/games ~/.config/containers/systemd
cp quadlet/chess-learner-local.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start chess-learner-local
```

Then open http://localhost:9292.

Your games are saved in `~/chess-learner/games`. Put PGN files there to see them
in the library.

| To | Run |
|---|---|
| Stop it | `systemctl --user stop chess-learner-local` |
| Start it again | `systemctl --user start chess-learner-local` |
| See its status | `systemctl --user status chess-learner-local` |
| Follow its logs | `journalctl --user -u chess-learner-local -f` |
| Update it | `git pull --recurse-submodules`, build the image again (step 3), then `systemctl --user restart chess-learner-local` |
| Remove it | Stop it, delete `~/.config/containers/systemd/chess-learner-local.container`, then `systemctl --user daemon-reload` |

To keep it running after you log out, and start it at boot before you log in,
run `sudo loginctl enable-linger $USER`.

To use a port other than 9292, change `PublishPort=` in the copied unit file,
then run `systemctl --user daemon-reload` and restart the service.

### Mac

In Terminal, from the `chess-learner` folder:

```bash
mkdir -p games
podman run -d --name chess-learner -p 127.0.0.1:9292:3000 \
  -v "$PWD/games:/app/games" localhost/chess-learner:standalone
```

Then open http://localhost:9292. Your games are saved in the `games` folder.

### Windows

In PowerShell, from the `chess-learner` folder:

```powershell
mkdir games
podman run -d --name chess-learner -p 127.0.0.1:9292:3000 `
  -v "${PWD}\games:/app/games" localhost/chess-learner:standalone
```

Then open http://localhost:9292. Your games are saved in the `games` folder.

### Mac and Windows: day to day

You only run `podman run` once. After that, the container is listed in
Podman Desktop's **Containers** page, which has start, stop, log and delete
buttons, or use these commands:

| To | Run |
|---|---|
| Stop it | `podman stop chess-learner` |
| Start it again | `podman start chess-learner` |
| Follow its logs | `podman logs -f chess-learner` |
| Update it | `git pull --recurse-submodules`, build the image again (step 3), then `podman rm -f chess-learner` and the `podman run` command again. Your games stay in the `games` folder |

The container runs inside the Podman machine, so it stops when the machine
does, for example when you restart your computer. To get it back, start the
machine (Podman Desktop does this when it opens, or run
`podman machine start`), then start the container.

(Linux uses Quadlet because it hands the container to systemd. Mac and Windows
have no systemd, so there the container is managed through Podman directly.)

## What to Do Next

1. Get a PGN from your favorite chess site.
2. Paste it into the text area on the home page.
3. Click "Analyze Game".

See the [README](README.md) for the rest.

## Using Docker Instead

`docker-compose.yml` still works: run `docker compose up`, then open
http://localhost:9292. Your games are saved in the `games` folder.

## Need More Help?

- Full installation instructions: [INSTALL.md](INSTALL.md)
- Usage guide: [README.md](README.md)
- Report issues: [GitHub Issues](../../issues)
