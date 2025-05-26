import { Chessboard } from "./3rdparty/cm-chessboard/Chessboard.js";
// We no longer need to import FEN directly as the backend will provide it.

document.addEventListener("DOMContentLoaded", () => {
    const boardContainer = document.getElementById("chessboard-container");
    if (!boardContainer) {
        console.error("Chessboard container not found!");
        return;
    }

    let board; // Chessboard instance, will be initialized after fetching initial FEN
    const assetsUrl = "/3rdparty-assets/cm-chessboard/"; // Path to cm-chessboard assets
    const moveInfoDisplay = document.getElementById("move-info-display");

    /**
     * Updates the move information display area.
     * @param {object|null} lastMoveData - Data about the last move, or null.
     */
    function updateMoveInfoDisplay(lastMoveData) {
        if (!moveInfoDisplay) return;

        if (lastMoveData) {
            const lm = lastMoveData;
            // Format: "1. e4" or "1... e5"
            let movePrefix = `${lm.number}${lm.turn === 'w' ? '.' : '...'}`;
            let displayText = `${movePrefix} ${lm.san}`;

            if (lm.comment && lm.comment.trim() !== "") {
                displayText += ` {${lm.comment.trim()}}`;
            }
            if (lm.nags && lm.nags.length > 0) {
                displayText += ` ${lm.nags.join(' ')}`;
            }
            moveInfoDisplay.textContent = displayText;
        } else {
            // Initial position or no move info
            moveInfoDisplay.textContent = "Game start.";
        }
    }

    /**
     * Fetches FEN from the backend and updates the chessboard.
     * @param {string} url - The API endpoint to fetch from.
     * @param {string} method - HTTP method (GET, POST, etc.).
     * @param {object|null} body - The request body for POST requests.
     */
    async function fetchAndUpdateBoard(url, method = 'GET', body = null) {
        try {
            const options = { method };
            if (body) {
                // For POST requests, we might send data, though not used in current next/prev
                // options.headers = { 'Content-Type': 'application/json' };
                // options.body = JSON.stringify(body);
            }
            const response = await fetch(url, options);
            const data = await response.json();

            if (!response.ok) {
                console.error(`Error from server ${url}: ${response.status} ${response.statusText}`, data.error || '');
                if (data.error && data.error.includes("Game not loaded")) {
                    alert("Game data is not loaded on the server. Please check server logs and ensure a PGN_FILE environment variable was correctly set when starting the server.");
                }
                return null;
            }

            if (data.fen) {
                if (!board) {
                    // Initialize board for the first time
                    const props = {
                        position: data.fen,
                        assetsUrl: assetsUrl
                    };
                    board = new Chessboard(boardContainer, props);
                    console.log(`Chessboard initialized. FEN: ${data.fen}, Position index: ${data.move_index}, Total positions: ${data.total_positions}`);
                } else {
                    // Update existing board
                    board.setPosition(data.fen, true); // true for animation
                    console.log(`Board updated. FEN: ${data.fen}, Position index: ${data.move_index}`);
                }
                updateMoveInfoDisplay(data.last_move); // Update move display

                if (data.message) { // Log server messages like "Already at last move"
                    console.log(`Server message: ${data.message}`);
                }

            } else if (data.error) {
                 console.error("Error from server:", data.error);
                 if (moveInfoDisplay && data.error.includes("Game not loaded")) {
                    moveInfoDisplay.textContent = "Error: Game not loaded on server.";
                 }
            }
            return data;
        } catch (error) {
            console.error(`Network or other error fetching from ${url}:`, error);
            // Display a more user-friendly error, e.g., in a status bar on the page
            alert(`Could not connect to the server or an error occurred. Please check the console for details and ensure the backend server is running. Error: ${error.message}`);
            return null;
        }
    }

    // Fetch initial board position when the page loads
    fetchAndUpdateBoard('/game/current_fen');

    // Event listeners for controls
    document.getElementById("prev-move")?.addEventListener("click", async () => {
        console.log("Previous move clicked");
        if (board) { // Ensure board is initialized
            await fetchAndUpdateBoard('/game/prev_move', 'POST');
        } else {
            console.warn("Board not initialized yet. Cannot go to previous move.");
            alert("Chessboard is not yet loaded. Please wait or check server status.");
        }
    });

    document.getElementById("next-move")?.addEventListener("click", async () => {
        console.log("Next move clicked");
        if (board) { // Ensure board is initialized
            await fetchAndUpdateBoard('/game/next_move', 'POST');
        } else {
            console.warn("Board not initialized yet. Cannot go to next move.");
            alert("Chessboard is not yet loaded. Please wait or check server status.");
        }
    });

    // Placeholder event listeners for other controls (unchanged)
    document.getElementById("next-critical")?.addEventListener("click", () => {
        console.log("Next critical moment clicked");
        // TODO: Implement logic
    });

    document.getElementById("learn-side")?.addEventListener("change", (event) => {
        console.log("Learn side changed to:", event.target.value);
        // TODO: Implement logic
    });
});
