# Installation Guide for Chess Learner

Choose the installation method that works best for you:

## Option 1: Docker/Podman

This is anyone who want to get it up and running without worrying about installing
lots of dependencies.

### What is Docker/Podman?
Docker (or Podman on Linux) packages the entire application with all its dependencies. You don't need to install Ruby, Node.js, or Stockfish separately - everything runs in an isolated container.

**Using Podman?** Podman is a Docker-compatible alternative that's popular on Linux. All Docker instructions work with Podman using `podman-compose` or the `podman-start.sh` script.

### Prerequisites
- **Docker Desktop** for [Windows](https://docs.docker.com/desktop/install/windows-install/) or [Mac](https://docs.docker.com/desktop/install/mac-install/)
- **Docker Engine** for [Linux](https://docs.docker.com/engine/install/)

### Installation Steps

#### Windows
1. Download and install [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/)
2. Open PowerShell or Command Prompt
3. Navigate to the chess learner directory:
   ```powershell
   cd path\to\chess\learner
   ```
4. Start the application:
   ```powershell
   docker-compose up
   ```
5. Open your browser to http://localhost:9292

To stop: Press `Ctrl+C` in the terminal

To restart later: Run `docker-compose up` again

#### Mac
1. Download and install [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)
2. Open Terminal
3. Navigate to the chess learner directory:
   ```bash
   cd path/to/chess/learner
   ```
4. Start the application:
   ```bash
   docker-compose up
   ```
5. Open your browser to http://localhost:9292

To stop: Press `Cmd+C` in the terminal

To restart later: Run `docker-compose up` again

#### Linux

**Option A: Using Podman**

Podman is a Docker-compatible alternative that doesn't require root privileges and is available in most Linux distributions.

1. Install Podman:
   ```bash
   sudo apt-get install podman         # Ubuntu/Debian
   # or
   sudo dnf install podman             # Fedora
   # or
   sudo pacman -S podman               # Arch
   ```

2. Navigate to the chess learner directory:
   ```bash
   cd path/to/chess/learner
   ```

3. Start the application:
   ```bash
   ./podman-start.sh
   ```

4. Open your browser to http://localhost:9292

To stop: `podman stop chess-learner`

To restart later: Run `./podman-start.sh` again

**Option B: Using Docker**

1. Install Docker Engine following your distro's instructions:
   - [Ubuntu/Debian](https://docs.docker.com/engine/install/ubuntu/)
   - [Fedora](https://docs.docker.com/engine/install/fedora/)
   - [Arch](https://wiki.archlinux.org/title/Docker)

2. Install Docker Compose:
   ```bash
   sudo apt-get install docker-compose  # Ubuntu/Debian
   # or
   sudo dnf install docker-compose      # Fedora
   # or
   sudo pacman -S docker-compose        # Arch
   ```

3. Add your user to the docker group (to avoid needing sudo):
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker  # Activate the group change
   ```

4. Navigate to the chess learner directory:
   ```bash
   cd path/to/chess/learner
   ```

5. Start the application:
   ```bash
   docker-compose up
   ```

6. Open your browser to http://localhost:9292

To stop: Press `Ctrl+C` in the terminal

To restart later: Run `docker-compose up` again

### Your Games
Analyzed games are automatically saved in the `games` directory in the chess learner folder. They persist even when you stop and restart the application.

### Running in the Background
To run the application in the background (so you can close the terminal):

```bash
docker-compose up -d
```

To stop it later:
```bash
docker-compose down
```

---

## Option 2: Native Installation (For Developers)

This is for developers who want to modify the code or prefer native installation.

### Prerequisites
- Ruby 3.2.3 or higher
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

### Docker Issues

**"Cannot connect to Docker daemon"** (Linux)
- Make sure Docker is running: `sudo systemctl start docker`
- Add your user to docker group: `sudo usermod -aG docker $USER`
- Log out and back in

**"Permission denied" with docker-compose and Podman**
- Use `podman-compose` instead: `pip3 install --user podman-compose`, then run `podman-compose up`
- Or use the provided script: `./podman-start.sh`
- Or use podman directly (see INSTALL.md Linux section)

**"Port 9292 already in use"**
- Another application is using port 9292
- Change the port in docker-compose.yml: `"8080:3000"` (changes to port 8080)

**"No space left on device"** (Docker)
- Clean up old Docker images: `docker system prune -a`

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
- For Docker issues, see [Docker documentation](https://docs.docker.com/)

## Next Steps

Once installed, see [README.md](README.md) for:
- How to upload and analyze games
- How to navigate through games
- How to practice at critical moments
