# Installation Guide for Chess Learner

Choose the installation method that works best for you:

## Option 1: Podman (recommended)

This is for anyone who wants it up and running without installing lots of
dependencies.

### What is Podman?

[Podman](https://podman.io) runs the application in a container: a packaged
copy of the application together with everything it needs. You don't need to
install Ruby, Node.js or Stockfish yourself.

- **Linux:** Podman runs containers directly. Chess Learner comes with a
  [Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
  unit, `quadlet/chess-learner-local.container`, so systemd starts the
  container when you log in and restarts it if it crashes.
- **Mac and Windows:** containers are Linux programs, so Podman runs them in a
  small Linux virtual machine, the *Podman machine*.
  [Podman Desktop](https://podman-desktop.io) sets it up for you (on Windows,
  with WSL 2). You start the container once with `podman run`, then manage it
  from Podman Desktop or with `podman start` and `podman stop`.

### Installation Steps

The [Quickstart Guide](QUICKSTART.md) has the steps for each platform: getting
the code, installing Podman, building the image and running it.

### Your Games

- **Linux (Quadlet):** games are saved in `~/chess-learner/games`.
- **Mac and Windows:** games are saved in the `games` folder inside the chess
  learner folder.

Either way they're on your computer, not inside the container, so they're kept
when you stop, update or remove the container. PGN files you put there appear
in the library.

### Using Docker Instead

`docker-compose.yml` still works with Docker Desktop or Docker Engine:

```bash
docker compose up        # or docker compose up -d to run in the background
docker compose down      # to stop it
```

Your games are saved in the `games` folder.

---

## Option 2: Native Installation (For Developers)

This is for developers who want to modify the code, or anyone who prefers not to use a container.

### Prerequisites
- Ruby 3.4. CI and the container image use the version in `.ruby-version`
  (currently 3.4.13). Distribution packages are often older; if yours is, a
  version manager such as [rbenv](https://github.com/rbenv/rbenv) or
  [mise](https://mise.jdx.dev) can install the version in `.ruby-version`.
- Node.js and npm
- Stockfish chess engine
- Bundler gem

### Installation by Platform

#### Windows (Native)

1. **Install Ruby:**
   - Download [RubyInstaller with DevKit](https://rubyinstaller.org/)
   - During installation, select "Add Ruby to PATH"
   - At the end, select "Run 'ridk install'" and choose option 3

2. **Install Node.js:**
   - Download [Node.js LTS](https://nodejs.org/)
   - Run the installer (includes npm)

3. **Install Stockfish:**
   - Download from [Stockfish website](https://stockfishchess.org/download/)
   - Extract stockfish.exe to a folder
   - Add that folder to your system PATH:
     - Search for "Environment Variables" in Windows
     - Edit "Path" variable
     - Add the folder containing stockfish.exe
     - Click OK

4. **Install the application:**
   ```powershell
   cd path\to\chess\learner
   gem install bundler
   bundle install
   npm install
   npm run copy-all
   ```

5. **Run the application:**
   ```powershell
   # Create a games directory if it doesn't exist
   mkdir games -Force

   # Set the PGN directory (do this each time you open a new terminal)
   $env:PGN_DIR=".\games"

   # Start the server
   bundle exec puma config.ru
   ```

6. Open http://localhost:9292

**Creating a startup script (Windows):**

Create a file called `start.bat`:
```batch
@echo off
set PGN_DIR=.\games
if not exist games mkdir games
bundle exec puma config.ru
pause
```

Then just double-click `start.bat` to run the application.

#### Mac (Native)

1. **Install Homebrew** (if not already installed):
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. **Install dependencies:**
   ```bash
   brew install ruby node stockfish
   ```

3. **Add Ruby to your PATH:**
   Add this to your `~/.zshrc` or `~/.bash_profile`:
   ```bash
   export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
   ```
   Then reload: `source ~/.zshrc`

4. **Install the application:**
   ```bash
   cd path/to/chess/learner
   gem install bundler
   bundle install
   npm install
   npm run copy-all
   ```

5. **Run the application:**
   ```bash
   # Create a games directory
   mkdir -p games

   # Set the PGN directory and start the server
   export PGN_DIR=./games
   bundle exec puma config.ru
   ```

6. Open http://localhost:9292

**Creating a startup script (Mac):**

Create a file called `start.sh`:
```bash
#!/bin/bash
export PGN_DIR=./games
mkdir -p games
bundle exec puma config.ru
```

Make it executable:
```bash
chmod +x start.sh
```

Then run: `./start.sh`

#### Linux (Native)

1. **Install dependencies:**

   **Ubuntu/Debian:**
   ```bash
   sudo apt-get update
   sudo apt-get install ruby-full nodejs npm stockfish build-essential
   ```

   **Fedora:**
   ```bash
   sudo dnf install ruby nodejs npm stockfish gcc make
   ```

   **Arch:**
   ```bash
   sudo pacman -S ruby nodejs npm stockfish base-devel
   ```

2. **Install the application:**
   ```bash
   cd path/to/chess/learner
   gem install bundler
   bundle install
   npm install
   npm run copy-all
   ```

3. **Run the application:**
   ```bash
   # Create a games directory
   mkdir -p games

   # Set the PGN directory and start the server
   export PGN_DIR=./games
   bundle exec puma config.ru
   ```

4. Open http://localhost:9292

**Creating a startup script (Linux):**

Create a file called `start.sh`:
```bash
#!/bin/bash
export PGN_DIR=./games
mkdir -p games
bundle exec puma config.ru
```

Make it executable:
```bash
chmod +x start.sh
```

Then run: `./start.sh`

---

## Troubleshooting

### Container Issues

**"Cannot connect to Podman"** (Mac and Windows)
- The Podman machine isn't running. Open Podman Desktop, or run
  `podman machine start`.

**The build fails while checking out or compiling Stockfish**
- The Stockfish submodule is missing. Run `git submodule update --init Stockfish`.

**"Illegal instruction" in the logs**
- Stockfish was built for a different CPU. Build the image again with the
  `STOCKFISH_ARCH` build argument for your computer (see
  [QUICKSTART.md](QUICKSTART.md), step 3).

**"Port 9292 already in use"**
- Another application is using port 9292. Choose another port, such as 8080:
  - Linux (Quadlet): set `PublishPort=127.0.0.1:8080:3000` in
    `~/.config/containers/systemd/chess-learner-local.container`, then run
    `systemctl --user daemon-reload` and
    `systemctl --user restart chess-learner-local`.
  - Mac and Windows: remove the container with `podman rm -f chess-learner`
    and run it again with `-p 127.0.0.1:8080:3000`.
- Then open http://localhost:8080.

**The service won't start** (Linux)
- See why with `systemctl --user status chess-learner-local` and
  `journalctl --user -u chess-learner-local`.
- If it can't find the image, build it (QUICKSTART.md, step 3). The unit uses
  `localhost/chess-learner:standalone`.

**"No space left on device"**
- Remove old images and stopped containers: `podman system prune`.

### Native Installation Issues

**"Command not found: ruby/node/stockfish"**
- The program isn't installed or isn't in your PATH
- Revisit the installation steps for your platform

**"Bundle install fails"** (Windows)
- Make sure you installed RubyInstaller with DevKit
- Run `ridk install` and choose option 3

**"Cannot find Stockfish"**
- Stockfish must be accessible from command line
- Test by typing `stockfish` in terminal - should start the engine
- On Windows, add stockfish.exe location to PATH

**Port 9292 in use**
- Another program is using the port
- Stop other applications or change the port in config.ru

---

## Getting Help

- Check [README.md](README.md) for usage instructions
- Report issues on GitHub
- For Podman issues, see the [Podman documentation](https://docs.podman.io/)

## Next Steps

Once installed, see [README.md](README.md) for:
- How to upload and analyze games
- How to navigate through games
- How to practice at critical moments
