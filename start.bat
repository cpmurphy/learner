@echo off
REM Chess Learner startup script for Windows

echo Chess Learner - Starting...
echo.

REM Create games directory if it doesn't exist
if not exist games mkdir games

REM Set environment variable
set PGN_DIR=.\games

REM Check if Ruby is installed
echo Checking dependencies...
ruby --version >nul 2>&1
if errorlevel 1 (
    echo Error: Ruby is not installed!
    echo Please see INSTALL.md for installation instructions.
    pause
    exit /b 1
)

REM Check if Node.js is installed
node --version >nul 2>&1
if errorlevel 1 (
    echo Error: Node.js is not installed!
    echo Please see INSTALL.md for installation instructions.
    pause
    exit /b 1
)

REM Check if Stockfish is installed
stockfish.exe quit >nul 2>&1
if errorlevel 1 (
    echo Error: Stockfish is not installed or not in PATH!
    echo Please see INSTALL.md for installation instructions.
    pause
    exit /b 1
)

REM Check if bundle install has been run
if not exist "vendor\bundle" (
    if not exist ".bundle\config" (
        echo Installing Ruby dependencies (this may take a few minutes on first run)...
        call bundle install
        if errorlevel 1 (
            echo Error installing Ruby dependencies!
            pause
            exit /b 1
        )
    )
)

REM Check if npm install has been run
if not exist "node_modules" (
    echo Installing JavaScript dependencies...
    call npm install
    if errorlevel 1 (
        echo Error installing JavaScript dependencies!
        pause
        exit /b 1
    )
)

REM Check if 3rdparty assets have been copied
if not exist "public\3rdparty-assets" (
    echo Copying third-party assets...
    call npm run copy-all
    if errorlevel 1 (
        echo Error copying assets!
        pause
        exit /b 1
    )
)

echo.
echo Starting server...
echo Once started, open your browser to: http://localhost:9292
echo.
echo Press Ctrl+C to stop the server.
echo.

bundle exec puma config.ru
pause
