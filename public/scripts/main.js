import { Chessboard } from "./3rdparty/cm-chessboard/Chessboard.js";
import { SanGenerator } from './san_generator.js';
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
    const pgnFileSelect = document.getElementById("pgn-file-select");
    const loadPgnButton = document.getElementById("load-pgn-button");
    const nextCriticalButton = document.getElementById("next-critical");


    let learningSide = learnSideSelect.value || 'white';
    let inCriticalMomentChallenge = false;
    let fenAtCriticalPrompt = null; // FEN before the bad move, for reverting
    let goodMoveSanForChallenge = null; // SAN of the good alternative move

    /**
     * Handles the user's move attempt during a critical moment challenge.
     * This function is passed to `board.enableMoveInput`.
     * @param {object} event - The event object from cm-chessboard, contains `squareFrom`, `squareTo`, `piece`.
     * @returns {boolean} - True if the move is allowed (correct), false otherwise.
     */
    async function handleCriticalMoveAttempt(event) {
        if (event.type !== 'moveInputFinished') {
            return; // Ignore non-moveInputFinished events
        }
        
        if (!inCriticalMomentChallenge || !goodMoveSanForChallenge) {
            console.warn("handleCriticalMoveAttempt called inappropriately.");
            return false;
        }

        let userMoveSan;
        try {
            const sanGenerator = new SanGenerator(fenAtCriticalPrompt, event.squareFrom, event.squareTo, event.promotionPiece);
            userMoveSan = sanGenerator.getSan();

            if (!userMoveSan) {
                // This implies the move was illegal by chess.js in SanGenerator,
                // or some other error occurred (e.g. invalid FEN, missing params).
                // The SanGenerator logs specifics.
                console.error("Critical Challenge - SanGenerator could not produce SAN. Move might be illegal or data inconsistent.", 
                              { from: event.squareFrom, to: event.squareTo, promotion: event.promotionPiece, fen: fenAtCriticalPrompt });
                moveInfoDisplay.textContent = "That move is not valid or could not be processed. Try again!";
                return false; // Reject the move, preventing cm-chessboard from visually making it.
            }
        } catch (e) { 
            // Catch any unexpected errors from SanGenerator instantiation or getSan() itself, though SanGenerator is designed to catch its own errors.
            console.error("Critical Challenge - Error generating SAN using SanGenerator:", e);
            moveInfoDisplay.textContent = "Error processing your move. Try again!";
            return false;
        }
        
        console.log(`Critical Challenge - User attempted: ${userMoveSan} (derived from ${event.squareFrom}-${event.squareTo}${event.promotionPiece ? "="+event.promotionPiece : ""}), Expected good move: ${goodMoveSanForChallenge}`);

        if (userMoveSan === goodMoveSanForChallenge) {
            moveInfoDisplay.textContent = `Correct! "${userMoveSan}" is a better move. Click 'Next Move' to continue the actual game.`;
            board.disableMoveInput();
            inCriticalMomentChallenge = false;
            return true;
        } else {
            moveInfoDisplay.textContent = `"${userMoveSan}" is not the best move. Try again!`;
            // Force the board to revert to the previous position
            board.setPosition(fenAtCriticalPrompt, false);
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
            let movePrefix = `${lm.number}${lm.turn === 'white' ? '.' : '...'}`;
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
                options.headers = { 'Content-Type': 'application/json' };
                options.body = JSON.stringify(body);
            }
            const response = await fetch(url, options);
            const data = await response.json();

            if (!response.ok) {
                console.error(`Error from server ${url}: ${response.status} ${response.statusText}`, data.error || '');
                const errorMsg = data.error || `Server error ${response.status}. Check console.`;
                if (moveInfoDisplay) moveInfoDisplay.textContent = `Error: ${errorMsg}`;
                
                if (errorMsg.includes("No game loaded")) {
                     if (url === '/game/current_fen' && !board) { 
                        moveInfoDisplay.textContent = "Please select a PGN file and load a game.";
                     }
                     if (nextCriticalButton) nextCriticalButton.disabled = true;
                } else if (errorMsg.includes("PGN_DIR environment variable not set") || errorMsg.includes("PGN directory not found")) {
                    alert("Server PGN directory not configured. Please check server logs.");
                    if (nextCriticalButton) nextCriticalButton.disabled = true;
                } else if (url === '/api/load_game') { 
                    alert(`Error loading game: ${errorMsg}`);
                    if (nextCriticalButton) nextCriticalButton.disabled = true;
                }
                return null;
            }
            
            if (data.message && (url === '/api/load_game' || url === '/game/next_move' || url === '/game/prev_move' || url === '/game/next_critical_moment')) { 
                console.log(`Server message: ${data.message}`);
            }


            if (data.fen || (data.last_move && data.last_move.fen_before_move) || (url === '/api/load_game' && data.fen)) { // Ensure there's a FEN to display or it's a load_game response with FEN
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

                if (!board) { // First time board initialization
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
                    // After initializing board on game load, check if "Next Critical" should be enabled
                    if (url === '/api/load_game' && nextCriticalButton) {
                        if (data.has_initial_critical_moment_for_white && learningSide === 'white') {
                            nextCriticalButton.disabled = false;
                        } else {
                            nextCriticalButton.disabled = true; 
                        }
                    }
                    // Enable prev/next buttons now that a game is loaded
                    if (prevMoveButton) prevMoveButton.disabled = false;
                    if (nextMoveButton) nextMoveButton.disabled = false;

                } else { // Board already exists, just updating position
                    board.setPosition(fenToDisplay, true); // true for animation
                    console.log(`Board updated. FEN: ${fenToDisplay}, Position index: ${data.move_index}`);
                }

                // General logic for enabling Next Critical button after any move, unless explicitly told no more.
                if (nextCriticalButton && board) {
                    if (url === '/game/next_critical_moment' && data.message && data.message.startsWith("No further critical moments found")) {
                        // This case is handled by the click handler itself to disable the button.
                    } else if (url !== '/api/load_game') { 
                        nextCriticalButton.disabled = false;
                    }
                }
                // Ensure prev/next buttons are enabled if board exists and it's not an error case
                if (board) {
                    if (prevMoveButton) prevMoveButton.disabled = false;
                    if (nextMoveButton) nextMoveButton.disabled = false;
                }


                if (setupChallenge) {
                    moveInfoDisplay.textContent = `Critical moment! The game move was ${lastMoveData.san}. That was a poor choice. Try a better move for ${learningSide}.`;
                    board.enableMoveInput(handleCriticalMoveAttempt, learningSide);
                } else {
                    updateMoveInfoDisplay(lastMoveData); 
                }
                
                if (data.message) { 
                    console.log(`Server message: ${data.message}`);
                }

            } else if (data.error) { // Handle errors from server (response not ok)
                 console.error("Error from server:", data.error);
                 if (moveInfoDisplay) { 
                    moveInfoDisplay.textContent = data.error || "An unspecified error occurred.";
                 }
                 if (nextCriticalButton) nextCriticalButton.disabled = true;
                 if (prevMoveButton) prevMoveButton.disabled = true;
                 if (nextMoveButton) nextMoveButton.disabled = true;
            }
            return data; 
        } catch (error) { 
            console.error(`Network or other error fetching from ${url}:`, error);
            alert(`Could not connect to the server or an error occurred. Please check the console for details. Error: ${error.message}`);
            if (moveInfoDisplay) moveInfoDisplay.textContent = "Network error or server unavailable.";
            if (nextCriticalButton) nextCriticalButton.disabled = true;
            if (prevMoveButton) prevMoveButton.disabled = true;
            if (nextMoveButton) nextMoveButton.disabled = true;
            return null;
        }
    }

    /**
     * Fetches the list of PGN files and populates the select dropdown.
     */
    async function loadPgnFileList() {
        if (!pgnFileSelect) return;
        try {
            const response = await fetch('/api/pgn_files');
            if (!response.ok) {
                pgnFileSelect.innerHTML = '<option value="">Error loading PGNs</option>';
                console.error("Failed to fetch PGN file list:", response.status, response.statusText);
                alert(`Failed to load PGN file list from server: ${response.statusText}. Check server logs and PGN_DIR configuration.`);
                if (loadPgnButton) loadPgnButton.disabled = true;
                if (nextCriticalButton) nextCriticalButton.disabled = true;
                return;
            }
            const pgnFiles = await response.json();
            if (pgnFiles.length === 0) {
                pgnFileSelect.innerHTML = '<option value="">No PGN files found</option>';
                if (loadPgnButton) loadPgnButton.disabled = true;
                if (nextCriticalButton) nextCriticalButton.disabled = true;
                if (moveInfoDisplay) moveInfoDisplay.textContent = "No PGN files found in the configured directory. Check server PGN_DIR.";
            } else {
                pgnFileSelect.innerHTML = '<option value="">-- Select a PGN --</option>'; // Placeholder
                pgnFiles.forEach(file => {
                    const option = document.createElement("option");
                    option.value = file.id;
                    option.textContent = file.name;
                    pgnFileSelect.appendChild(option);
                });
                if (loadPgnButton) loadPgnButton.disabled = false;
                if (moveInfoDisplay) moveInfoDisplay.textContent = "Please select a PGN file and load a game.";
            }
        } catch (error) {
            pgnFileSelect.innerHTML = '<option value="">Error loading PGNs</option>';
            console.error("Error fetching PGN file list:", error);
            alert(`Error fetching PGN file list: ${error.message}. Is the server running?`);
            if (loadPgnButton) loadPgnButton.disabled = true;
            if (nextCriticalButton) nextCriticalButton.disabled = true;
        }
    }

    // Initial setup
    if (nextCriticalButton) nextCriticalButton.disabled = true; // Initially disabled
    const prevMoveButton = document.getElementById("prev-move");
    const nextMoveButton = document.getElementById("next-move");

    if (prevMoveButton) prevMoveButton.disabled = true;
    if (nextMoveButton) nextMoveButton.disabled = true;
    
    loadPgnFileList(); // Load PGN files on page load
    // Board is not initialized until a game is loaded.
    // Initial message is set within loadPgnFileList or if it fails.

    // Event listeners for controls
    pgnFileSelect?.addEventListener("change", () => {
        if (board) {
            board.destroy();
            board = null;
        }
        if (moveInfoDisplay) {
            if (pgnFileSelect.value) {
                moveInfoDisplay.textContent = "PGN file selected. Click 'Load First Game' to load.";
            } else {
                moveInfoDisplay.textContent = "Please select a PGN file and load a game.";
            }
        }
        // Disable navigation buttons as no game is actively loaded into the board
        if (nextCriticalButton) nextCriticalButton.disabled = true;
        if (prevMoveButton) prevMoveButton.disabled = true;
        if (nextMoveButton) nextMoveButton.disabled = true;
        // loadPgnButton should be enabled if a file is selected, disabled if "-- Select a PGN --" is chosen
        if (loadPgnButton) loadPgnButton.disabled = !pgnFileSelect.value; 
    });

    loadPgnButton?.addEventListener("click", async () => {
        const selectedPgnId = pgnFileSelect.value;
        if (!selectedPgnId) {
            alert("Please select a PGN file from the dropdown.");
            return;
        }
        console.log(`Loading game from PGN ID: ${selectedPgnId}`);
        // fetchAndUpdateBoard will handle initializing or updating the board
        // and displaying initial move info or "Game start."
        const gameData = await fetchAndUpdateBoard('/api/load_game', 'POST', { pgn_file_id: selectedPgnId });
        if (gameData && gameData.fen) { 
             if (moveInfoDisplay && !gameData.last_move) moveInfoDisplay.textContent = "Game loaded. Ready to start.";
             // The logic within fetchAndUpdateBoard now handles enabling/disabling nextCriticalButton
             // based on data.has_initial_critical_moment_for_white and current learningSide.
        } else if (!gameData) { 
            if (moveInfoDisplay) moveInfoDisplay.textContent = "Failed to load game. Check console or select another file.";
            // nextCriticalButton is disabled by fetchAndUpdateBoard in case of error or if board doesn't init
        }
    });

    document.getElementById("prev-move")?.addEventListener("click", async () => {
        console.log("Previous move clicked");
        if (board) {
            await fetchAndUpdateBoard('/game/prev_move', 'POST');
        } else {
            alert("Please load a game first using the 'Load First Game' button.");
        }
    });

    document.getElementById("next-move")?.addEventListener("click", async () => {
        console.log("Next move clicked");
        if (board) {
            await fetchAndUpdateBoard('/game/next_move', 'POST');
        } else {
            alert("Please load a game first using the 'Load First Game' button.");
        }
    });

    // Event listener for "Next Critical Moment" button
    nextCriticalButton?.addEventListener("click", async () => {
        console.log("Next critical moment clicked");
        if (!board) { // Check if a game is loaded
            alert("Please load a game first using the 'Load First Game' button.");
            return;
        }
        if (!learningSide) {
            console.error("Learning side not selected.");
            alert("Error: Learning side not selected.");
            return;
        }

        const responseData = await fetchAndUpdateBoard('/game/next_critical_moment', 'POST', { learning_side: learningSide });

        if (responseData) {
            if (responseData.message && responseData.message.startsWith("No further critical moments found")) {
                alert(responseData.message); // Inform the user
                if (nextCriticalButton) nextCriticalButton.disabled = true; // Disable the button
            }
            // If a critical moment was found, fetchAndUpdateBoard handled the UI update.
            // The general enabling logic in fetchAndUpdateBoard ensures it's enabled if the board is valid
            // and it wasn't a "no more critical" response.
        }
        // If responseData is null, fetchAndUpdateBoard already handled error display and button state.
    });

    learnSideSelect?.addEventListener("change", (event) => {
        learningSide = event.target.value;
        console.log("Learning side changed to:", learningSide);
        if (inCriticalMomentChallenge) {
            console.log("Learning side changed during a critical challenge. Challenge cancelled.");
            inCriticalMomentChallenge = false;
            if (board) board.disableMoveInput();
            fetchAndUpdateBoard('/game/current_fen'); 
        }
        // If a game is loaded, changing learning side should re-enable the next critical button.
        // The click on the button will then verify if a critical moment exists for the new side.
        if (board && nextCriticalButton) {
            nextCriticalButton.disabled = false;
        }
    });
});
