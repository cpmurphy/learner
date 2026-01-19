#!/bin/bash
# Chess Learner startup script for Podman
# This script provides a simple way to run Chess Learner with Podman

set -e

IMAGE_NAME="chess-learner"
CONTAINER_NAME="chess-learner"
PORT="9292"
GAMES_DIR="./games"

echo "Chess Learner - Podman Startup"
echo "==============================="
echo ""

# Create games directory if it doesn't exist
if [ ! -d "$GAMES_DIR" ]; then
    echo "Creating games directory..."
    mkdir -p "$GAMES_DIR"
fi

# Check if container already exists
if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container '$CONTAINER_NAME' exists."

    # Check if it's running
    if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container is already running!"
        echo "Open your browser to: http://localhost:$PORT"
        exit 0
    else
        echo "Starting existing container..."
        podman start "$CONTAINER_NAME"
        echo ""
        echo "Container started successfully!"
        echo "Open your browser to: http://localhost:$PORT"
        echo ""
        echo "To stop: podman stop $CONTAINER_NAME"
        echo "To view logs: podman logs -f $CONTAINER_NAME"
        exit 0
    fi
fi

# Check if image exists
if ! podman images --format "{{.Repository}}" | grep -q "^${IMAGE_NAME}$"; then
    echo "Image '$IMAGE_NAME' not found. Building..."
    echo "This may take 5-10 minutes on first run..."
    echo ""
    podman build -t "$IMAGE_NAME" .
    echo ""
    echo "Image built successfully!"
else
    echo "Using existing image '$IMAGE_NAME'"
fi

# Make sure games directory is writable
chmod 755 "$GAMES_DIR" 2>/dev/null || true

# Run the container
# Note: Using :z (lowercase) for SELinux shared label, and --userns=keep-id to preserve UID mapping
echo "Starting new container..."
podman run -d \
    -p "$PORT:3000" \
    -v "$GAMES_DIR:/app/games:z" \
    -e PGN_DIR=/app/games \
    --userns=keep-id \
    --name "$CONTAINER_NAME" \
    "$IMAGE_NAME"

echo ""
echo "Container started successfully!"
echo "Open your browser to: http://localhost:$PORT"
echo ""
echo "Useful commands:"
echo "  Stop:       podman stop $CONTAINER_NAME"
echo "  Start:      podman start $CONTAINER_NAME"
echo "  Remove:     podman stop $CONTAINER_NAME && podman rm $CONTAINER_NAME"
echo "  View logs:  podman logs -f $CONTAINER_NAME"
echo "  Rebuild:    podman build -t $IMAGE_NAME ."
