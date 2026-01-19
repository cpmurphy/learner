#!/bin/bash
# Chess Learner startup script for Mac/Linux

set -e

echo "Chess Learner - Starting..."
echo ""

# Create games directory if it doesn't exist
if [ ! -d "games" ]; then
    echo "Creating games directory..."
    mkdir -p games
fi

# Set environment variable
export PGN_DIR=./games

# Check if dependencies are installed
echo "Checking dependencies..."

if ! command -v ruby &> /dev/null; then
    echo "Error: Ruby is not installed!"
    echo "Please see INSTALL.md for installation instructions."
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed!"
    echo "Please see INSTALL.md for installation instructions."
    exit 1
fi

if ! command -v stockfish &> /dev/null; then
    echo "Error: Stockfish is not installed!"
    echo "Please see INSTALL.md for installation instructions."
    exit 1
fi

# Check if bundle install has been run
if [ ! -d "vendor/bundle" ] && [ ! -f ".bundle/config" ]; then
    echo "Installing Ruby dependencies (this may take a few minutes on first run)..."
    bundle install
fi

# Check if npm install has been run
if [ ! -d "node_modules" ]; then
    echo "Installing JavaScript dependencies..."
    npm install
fi

# Check if 3rdparty assets have been copied
if [ ! -d "public/3rdparty-assets" ]; then
    echo "Copying third-party assets..."
    npm run copy-all
fi

echo ""
echo "Starting server..."
echo "Once started, open your browser to: http://localhost:9292"
echo ""
echo "Press Ctrl+C to stop the server."
echo ""

bundle exec puma config.ru
