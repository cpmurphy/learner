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
    const learnSideSelect = document.getElementById("learn-side");

    let learningSide = 'white'; // Default, updated by selector
    let inCriticalMomentChallenge = false;
    let fenAtCriticalPrompt = null; // FEN before the bad move, for reverting
    let goodMoveSanForChallenge = null; // SAN of the good alternative move

    /**
     * Handles the user's move attempt during a critical moment challenge.
     * This function is passed to `board.enableMoveInput`.
     * @param {object} event - The event object from cm-chessboard, contains `san`, `squareFrom`, `squareTo`, `piece`.
     * @returns {boolean} - True if the move is allowed (correct), false otherwise.
     */
    async function handleCriticalMoveAttempt(event) {
        if (!inCriticalMomentChallenge || !goodMoveSanForChallenge) {
            // This should ideally not be reached if input is managed correctly
            console.warn("handleCriticalMoveAttempt called inappropriately.");
            return false; 
        }

        const userMoveSan = event.san;
        console.log(`Critical Challenge - User attempted: ${userMoveSan}, Expected good move: ${goodMoveSanForChallenge}`);

        if (userMoveSan === goodMoveSanForChallenge) {
            moveInfoDisplay.textContent = `Correct! "${userMoveSan}" is a better move. Click 'Next Move' to continue the actual game.`;
            board.disableMoveInput();
            // board.addMarker(MARKER_TYPE.square, event.squareTo); // Optional: highlight the move
            inCriticalMomentChallenge = false; // Challenge resolved
            return true; // Allow cm-chessboard to make the move on the board
        } else {
            moveInfoDisplay.textContent = `"${userMoveSan}" is not the best move. Try again!`;
            // Returning false prevents cm-chessboard from making the move, effectively reverting.
            return false; 
        }
    }
    
    /**
     * Updates the move information display area.
     * @param {object|null} lastMoveData - Data about the last move, or null.
     */
    function updateMoveInfoDisplay(lastMoveData) {
        if (!moveInfoDisplay) return;

        if (lastMoveData) {
            // This function is for displaying the *actual last game move* information,
            // not for critical challenge prompts.
            const lm = lastMoveData;
            let movePrefix = `${lm.number}${lm.turn === 'w' ? '.' : '...'}`;
            let displayText = `${movePrefix} ${lm.san}`;

            if (lm.comment && lm.comment.trim() !== "") {
                displayText += ` {${lm.comment.trim()}}`;
            }
            if (lm.annotation && lm.annotation.length > 0) { // Changed from nags to annotation for consistency with backend
                displayText += ` ${lm.annotation.join(' ')}`;
            }

            // Add a note if it was a critical move by the opponent
            if (lm.is_critical && lm.turn !== learningSide) {
                displayText += ` (Opponent's blunder!)`;
            }
            moveInfoDisplay.textContent = displayText;
        } else {
            moveInfoDisplay.textContent = "Game start."; // Initial position or no move info
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
                    if (moveInfoDisplay) moveInfoDisplay.textContent = "Error: Game not loaded on server.";
                }
                return null;
            }

            if (data.fen || (data.last_move && data.last_move.fen_before_move)) { // Ensure there's a FEN to display
                const lastMoveData = data.last_move;
                let setupChallenge = false;

                // Check conditions for starting a critical moment challenge
                if (lastMoveData && lastMoveData.is_critical && lastMoveData.turn === learningSide && lastMoveData.good_move_san && lastMoveData.fen_before_move) {
                    setupChallenge = true;
                    inCriticalMomentChallenge = true;
                    fenAtCriticalPrompt = lastMoveData.fen_before_move;
                    goodMoveSanForChallenge = lastMoveData.good_move_san;
                } else {
                    inCriticalMomentChallenge = false;
                    if (board) board.disableMoveInput(); // Ensure input is disabled if not in challenge mode
                }

                const fenToDisplay = setupChallenge ? fenAtCriticalPrompt : data.fen;

                if (!board) {
                    // Initialize board for the first time
                    const props = {
                        position: fenToDisplay,
                        assetsUrl: assetsUrl,
                        style: {
                            moveFromMarker: undefined, // Optional: clear markers
                            moveToMarker: undefined,   // Optional: clear markers
                        }
                    };
                    board = new Chessboard(boardContainer, props);
                    console.log(`Chessboard initialized. FEN: ${fenToDisplay}, Position index: ${data.move_index}, Total positions: ${data.total_positions}`);
                } else {
                    // Update existing board
                    board.setPosition(fenToDisplay, true); // true for animation
                    console.log(`Board updated. FEN: ${fenToDisplay}, Position index: ${data.move_index}`);
                }

                if (setupChallenge) {
                    moveInfoDisplay.textContent = `Critical moment! The game move was ${lastMoveData.san}. That was a poor choice. Try a better move for ${learningSide}.`;
                    board.enableMoveInput(handleCriticalMoveAttempt, learningSide === 'w' ? 'white' : 'black');
                } else {
                    // Not a challenge, or challenge conditions not met. Display regular move info.
                    updateMoveInfoDisplay(lastMoveData); // This will also note opponent's blunders
                }
                
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
        // TODO: Implement logic for jumping to the next critical move.
        // This would involve a new backend endpoint or modifying existing ones.
    });

    learnSideSelect?.addEventListener("change", (event) => {
        learningSide = event.target.value;
        console.log("Learning side changed to:", learningSide);
        // If currently in a challenge, changing sides might be complex.
        // For now, this change will apply to the next critical moment encountered.
        // If a board is loaded and in a challenge, ideally, we might want to reset the challenge or re-evaluate.
        // Simplest: if inCriticalMomentChallenge, changing side cancels it.
        if (inCriticalMomentChallenge) {
            console.log("Learning side changed during a critical challenge. Challenge cancelled.");
            inCriticalMomentChallenge = false;
            board.disableMoveInput();
            // Re-fetch current game state to display normally without challenge
            fetchAndUpdateBoard('/game/current_fen'); 
        }
    });
});
