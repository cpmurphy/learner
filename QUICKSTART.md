# Quick Start Guide

## Fastest Way to Get Started

All options here involve Docker and/or Podman. If you want to run native on
your platform, see the [full installation instructions](INSTALL.md).

### Already Have Docker?
```bash
docker-compose up
```
Then open http://localhost:9292

### Already Have Podman?
```bash
./podman-start.sh
```
Then open http://localhost:9292

That's it! Your games are saved in the `games` folder.

### Don't Have Docker Yet?

Pick your platform:
- [Windows Instructions](#windows)
- [Mac Instructions](#mac)
- [Linux Instructions](#linux)

---

### Windows

1. Install [Docker Desktop](https://docs.docker.com/desktop/install/windows-install/)
2. Open PowerShell in the chess learner folder
3. Run: `docker-compose up`
4. Open: http://localhost:9292

### Mac

1. Install [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/)
2. Open Terminal in the chess learner folder
3. Run: `docker-compose up`
4. Open: http://localhost:9292

### Linux

**Ubuntu/Debian:**
```bash
sudo apt-get install docker.io docker-compose
sudo usermod -aG docker $USER
newgrp docker
docker-compose up
```

**Fedora:**
```bash
sudo dnf install docker docker-compose
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker
docker-compose up
```

**Arch:**
```bash
sudo pacman -S docker docker-compose
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker
docker-compose up
```

Then open: http://localhost:9292

---

## What to Do After Installation

   - Get a PGN from your favorite chess site
   - Paste it into the text area on the home page
   - Click "Analyze Game"

## Need More Help?

- Full installation instructions: [INSTALL.md](INSTALL.md)
- Usage guide: [README.md](README.md)
- Report issues: [GitHub Issues](../../issues)

## Stopping the Application

`Ctrl+C` in the terminal (or `docker-compose down`)
