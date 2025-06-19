import { Chessboard, COLOR } from "./3rdparty/cm-chessboard/Chessboard.js";
import { SanGenerator } from './san_generator.js';
import { Chess } from './3rdparty/chess.js/chess.js';
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
    const playerNamesDisplay = document.getElementById("player-names-display");
    const copyFenButton = document.getElementById("copy-fen-button");
    const fastRewindButton = document.getElementById("fast-rewind-moves");
    const fastForwardButton = document.getElementById("fast-forward-moves");
    const flipBoardButton = document.getElementById("flip-board");
    const resumeGameButton = document.getElementById("resume-game");


    let learningSide = learnSideSelect.value || 'white';
    let inCriticalMomentChallenge = false;
    let fenAtCriticalPrompt = null; // FEN before the bad move, for reverting
    let goodMoveSanForChallenge = null; // SAN of the good alternative move
    let lastKnownServerFEN = null; // Stores the last FEN received from the server for the main line

    // State for variation play
    let inVariationMode = false;
    let mainLineMoveIndexAtVariationStart = 0;
    let currentVariationSANs = [];
    let currentVariationPly = 0;
    let currentFenInVariation = null;

    /**
     * Converts a SAN move to square coordinates for cm-chessboard's movePiece method.
     * @param {string} san - The SAN move string (e.g., "e4", "Nf3", "O-O")
     * @param {string} fen - The FEN string representing the current board position
     * @returns {object|null} - Object with from and to square coordinates, or null if invalid
     */
    function sanToSquares(san, fen) {
        if (!fen || typeof fen !== 'string') {
            console.error("sanToSquares: Invalid FEN parameter:", fen);
            return null;
        }

        // Basic FEN validation - should have 6 space-delimited fields
        const fenParts = fen.trim().split(/\s+/);
        if (fenParts.length !== 6) {
            console.error("sanToSquares: FEN must have 6 space-delimited fields, got:", fenParts.length, "parts:", fenParts);
            return null;
        }

        try {
            const chess = new Chess(fen);
            const move = chess._moveFromSan(san, false); // Use non-strict parsing for PGN SANs

            if (move) {
                // Convert internal 0x88 coordinates to algebraic notation
                // file = square & 0xf, rank = square >> 4
                const fromSquare = 'abcdefgh'.substring(move.from & 0xf, (move.from & 0xf) + 1) +
                                 '87654321'.substring(move.from >> 4, (move.from >> 4) + 1);
                const toSquare = 'abcdefgh'.substring(move.to & 0xf, (move.to & 0xf) + 1) +
                               '87654321'.substring(move.to >> 4, (move.to >> 4) + 1);
                return { from: fromSquare, to: toSquare };
            }
            return null;
        } catch (e) {
            console.error("Error converting SAN to squares:", e);
            return null;
        }
    }

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
                // Ensure board is reset to the state before the attempted invalid move.
                if (board && fenAtCriticalPrompt) {
                    board.setPosition(fenAtCriticalPrompt, false); // false for no animation
                }
                return false; // Reject the move.
            }
        } catch (e) {
            // Catch any unexpected errors from SanGenerator instantiation or getSan() itself, though SanGenerator is designed to catch its own errors.
            console.error("Critical Challenge - Error generating SAN using SanGenerator:", e);
            moveInfoDisplay.textContent = "Error processing your move. Try again!";
            // Ensure board is reset if an unexpected error occurs during SAN generation.
            if (board && fenAtCriticalPrompt) {
                board.setPosition(fenAtCriticalPrompt, false); // false for no animation
            }
            return false;
        }

        console.log(`Critical Challenge - User attempted: ${userMoveSan} (derived from ${event.squareFrom}-${event.squareTo}${event.promotionPiece ? "="+event.promotionPiece : ""}), Expected good move: ${goodMoveSanForChallenge}`);

        if (userMoveSan === goodMoveSanForChallenge) {
            // Correct move in challenge! Enter variation mode.
            const lastMoveDataForVariation = window.lastServerMoveData; // Use cached lastMoveData that contained variation info

            if (lastMoveDataForVariation && lastMoveDataForVariation.variation_sans && lastMoveDataForVariation.variation_sans.length > 0) {
                inVariationMode = true;
                mainLineMoveIndexAtVariationStart = lastMoveDataForVariation.move_index_of_blunder; // Need to ensure this is correctly set
                currentVariationSANs = lastMoveDataForVariation.variation_sans;
                currentVariationPly = 0; // They just played the first move (index 0) of the variation

                // cm-chessboard's getPosition() only returns the board part, not the full FEN
                // We need to create a proper FEN from the last known server FEN and the move that was just made
                const boardPosition = board.getPosition(); // This is just the board part like "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
                if (lastKnownServerFEN) {
                    // Update the board part of the last known FEN with the current board position
                    const fenParts = lastKnownServerFEN.split(' ');
                    fenParts[0] = boardPosition; // Replace the board part

                    // Determine the correct turn for the variation
                    // The player just made the first move (variationPly = 0), so the next turn should be the opposite side
                    const nextTurn = learningSide === 'white' ? 'b' : 'w';
                    fenParts[1] = nextTurn;

                    // Reset move counters for variation
                    fenParts[4] = '0'; // halfmove clock
                    fenParts[5] = '1'; // fullmove number
                    currentFenInVariation = fenParts.join(' ');
                } else {
                    // Fallback: create a minimal FEN with just the board and turn
                    const nextTurn = learningSide === 'white' ? 'b' : 'w';
                    currentFenInVariation = `${boardPosition} ${nextTurn} KQkq - 0 1`;
                }

                moveInfoDisplay.textContent = `Correct! "${userMoveSan}" starts a good variation. Use 'Next Move' to explore it.`;
                if (resumeGameButton) resumeGameButton.disabled = false;
                if (nextMoveButton) nextMoveButton.disabled = false; // Enable for variation
                if (prevMoveButton) prevMoveButton.disabled = true; // Disable prev for variation for now
                if (nextCriticalButton) nextCriticalButton.disabled = true; // No new critical search while in variation
            } else {
                // Should not happen if goodMoveSanForChallenge was set, but as a fallback:
                moveInfoDisplay.textContent = `Correct! "${userMoveSan}" is a better move. Main game continues.`;
            }

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
    function updateMoveInfoDisplay(lastMoveData, isVariationMove = false, variationPly = 0) {
        if (!moveInfoDisplay) return;

        if (isVariationMove && lastMoveData && lastMoveData.san) { // lastMoveData here is just { san: '...' }
            const moveNumberInVariation = Math.floor(variationPly / 2) + 1;
            const turnInVariation = variationPly % 2 === 0 ? learningSide : (learningSide === 'white' ? 'black' : 'white'); // Assuming player makes first var move
            let movePrefix = `${moveNumberInVariation}${turnInVariation === 'white' ? '.' : '...'}`;
            moveInfoDisplay.textContent = `Variation: ${movePrefix} ${lastMoveData.san}`;
        } else if (lastMoveData) {
            const lm = lastMoveData;
            let movePrefix = `${lm.number}${lm.turn === 'white' ? '.' : '...'}`;
            let displayText = `${movePrefix} ${lm.san}`;

            if (lm.comment && lm.comment.trim() !== "") {
                displayText += ` {${lm.comment.trim()}}`;
            }
            if (lm.annotation && lm.annotation.length > 0) {
                displayText += ` ${lm.annotation.join(' ')}`;
            }
            if (lm.is_critical && lm.turn !== learningSide) {
                displayText += ` (Opponent's blunder!)`;
            }
            moveInfoDisplay.textContent = displayText;
        } else {
            moveInfoDisplay.textContent = "Game start.";
        }
    }

    /**
     * Fetches FEN from the backend and updates the chessboard.
     * @param {string} url - The API endpoint to fetch from.
     * @param {string} method - HTTP method (GET, POST, etc.).
     * @param {object|null} body - The request body for POST requests.
     */
    // Cache last server move data that might contain variation info
    // This is a bit of a hack; ideally, this context would be managed more cleanly.
    window.lastServerMoveData = null;

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
                if (playerNamesDisplay) playerNamesDisplay.textContent = "";

                if (errorMsg.includes("No game loaded")) {
                     if (url === '/game/current_fen' && !board) {
                        moveInfoDisplay.textContent = "Please select a PGN file and load a game.";
                     }
                } else if (errorMsg.includes("PGN_DIR environment variable not set") || errorMsg.includes("PGN directory not found")) {
                    alert("Server PGN directory not configured. Please check server logs.");
                } else if (url === '/api/load_game') {
                    alert(`Error loading game: ${errorMsg}`);
                }
                // Disable all navigation buttons on error
                if (nextCriticalButton) nextCriticalButton.disabled = true;
                if (prevMoveButton) prevMoveButton.disabled = true;
                if (nextMoveButton) nextMoveButton.disabled = true;
                if (copyFenButton) copyFenButton.disabled = true;
                if (fastRewindButton) fastRewindButton.disabled = true;
                if (fastForwardButton) fastForwardButton.disabled = true;
                if (flipBoardButton) flipBoardButton.disabled = true;
                if (resumeGameButton) resumeGameButton.disabled = true;
                inVariationMode = false; // Exit variation mode on error
                return null;
            }

            // Cache data if it contains last_move info, for variation handling
            if (data.last_move) {
                window.lastServerMoveData = { ...data.last_move, move_index_of_blunder: data.move_index };
            }

            // Update the last known FEN from the server if provided
            if (data.fen) {
                lastKnownServerFEN = data.fen;
            }

            if (data.message && (url === '/api/load_game' || url === '/game/next_move' || url === '/game/prev_move' || url === '/game/next_critical_moment' || url === '/game/set_move_index')) {
                console.log(`Server message: ${data.message}`);
            }

            if (playerNamesDisplay && data.white_player && data.black_player) {
                playerNamesDisplay.textContent = `${data.white_player} vs ${data.black_player}`;
            } else if (playerNamesDisplay) {
                // Clear if names are not in data, e.g. before game load or if API doesn't send them
                // playerNamesDisplay.textContent = "";
                // Decided to only clear on explicit error or no game loaded scenarios.
                // If a game is loaded, names should persist.
            }


            if (data.fen || (data.last_move && data.last_move.fen_before_move) || (url === '/api/load_game' && data.fen)) { // Ensure there's a FEN to display or it's a load_game response with FEN
                const lastMoveData = data.last_move;
                let setupChallenge = false;

                // Always disable move input before deciding to enable it for a new challenge,
                // or if no challenge is being set up. This prevents "moveInput already enabled" errors.
                if (board) {
                    board.disableMoveInput();
                }

                // Check conditions for starting a critical moment challenge
                if (lastMoveData && lastMoveData.is_critical && lastMoveData.turn === learningSide && lastMoveData.good_move_san && lastMoveData.fen_before_move) {
                    setupChallenge = true;
                    inCriticalMomentChallenge = true;
                    fenAtCriticalPrompt = lastMoveData.fen_before_move;
                    goodMoveSanForChallenge = lastMoveData.good_move_san;
                } else {
                    inCriticalMomentChallenge = false;
                    // board.disableMoveInput(); // Now called unconditionally above
                }

                // If we successfully set move index (e.g. resuming game), exit variation mode.
                if (url === '/game/set_move_index' || url === '/api/load_game' || url === '/game/go_to_start' || url === '/game/go_to_end') {
                    inVariationMode = false;
                    if (resumeGameButton) resumeGameButton.disabled = true;
                }

                const fenToDisplay = setupChallenge ? fenAtCriticalPrompt : data.fen;

                if (!board) { // First time board initialization
                    const initialOrientation = learningSide === 'white' ? COLOR.white : COLOR.black;
                    const props = {
                        position: fenToDisplay,
                        assetsUrl: assetsUrl,
                        style: {
                            moveFromMarker: undefined, // Optional: clear markers
                            moveToMarker: undefined,   // Optional: clear markers
                        },
                        orientation: initialOrientation
                    };
                    board = new Chessboard(boardContainer, props);
                    console.log(`Chessboard initialized. FEN: ${fenToDisplay}, Position index: ${data.move_index}, Total positions: ${data.total_positions}, Orientation: ${learningSide}`);
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
                    if (copyFenButton) copyFenButton.disabled = false;
                    if (fastRewindButton) fastRewindButton.disabled = !inVariationMode;
                    if (fastForwardButton) fastForwardButton.disabled = !inVariationMode;
                    if (flipBoardButton) flipBoardButton.disabled = false; // Flip board always available if board exists
                    if (resumeGameButton) resumeGameButton.disabled = !inVariationMode;

                } else { // Board already exists, just updating position
                    board.setPosition(fenToDisplay, true); // true for animation
                    console.log(`Board updated. FEN: ${fenToDisplay}, Position index: ${data.move_index}`);
                }

                // Button states based on mode
                if (inVariationMode) {
                    if (nextCriticalButton) nextCriticalButton.disabled = true;
                    if (prevMoveButton) prevMoveButton.disabled = true; // Prev in variation not supported yet
                    if (nextMoveButton) nextMoveButton.disabled = (currentVariationPly >= currentVariationSANs.length -1);
                    if (fastRewindButton) fastRewindButton.disabled = true;
                    if (fastForwardButton) fastForwardButton.disabled = true;
                    if (resumeGameButton) resumeGameButton.disabled = false;
                } else { // Main line play
                    if (nextCriticalButton && board) {
                         // Enable if not explicitly told no more criticals for this side
                        const noMoreCriticals = url === '/game/next_critical_moment' && data.message && data.message.startsWith("No further critical moments found");
                        if (url === '/api/load_game') { // Special handling for initial load
                             nextCriticalButton.disabled = !(data.has_initial_critical_moment_for_white && learningSide === 'white');
                        } else {
                            nextCriticalButton.disabled = noMoreCriticals;
                        }
                    }
                    if (prevMoveButton) prevMoveButton.disabled = (data.move_index === 0);
                    if (nextMoveButton) nextMoveButton.disabled = (data.move_index >= data.total_positions - 1);
                    if (fastRewindButton) fastRewindButton.disabled = (data.move_index === 0);
                    if (fastForwardButton) fastForwardButton.disabled = (data.move_index >= data.total_positions - 1);
                    if (resumeGameButton) resumeGameButton.disabled = true;
                }
                if (copyFenButton) copyFenButton.disabled = !board; // Enabled if board exists
                if (flipBoardButton) flipBoardButton.disabled = !board;


                if (setupChallenge) {
                    moveInfoDisplay.textContent = `The move was ${lastMoveData.san}. Try a better move for ${learningSide}.`;
                    board.enableMoveInput(handleCriticalMoveAttempt, learningSide);
                } else if (!inVariationMode) { // Don't update with main line move if we just entered variation
                    updateMoveInfoDisplay(lastMoveData);
                }
                // If in variation mode, move info is updated by "Next Move" (variation) handler.

                if (data.message) {
                    console.log(`Server message: ${data.message}`);
                }

            } else if (data.error) {
                 console.error("Error from server:", data.error);
                 if (moveInfoDisplay) {
                    moveInfoDisplay.textContent = data.error || "An unspecified error occurred.";
                 }
                 if (playerNamesDisplay) playerNamesDisplay.textContent = "";
                 // Disable all navigation buttons on error
                 if (nextCriticalButton) nextCriticalButton.disabled = true;
                 if (prevMoveButton) prevMoveButton.disabled = true;
                 if (nextMoveButton) nextMoveButton.disabled = true;
                 if (copyFenButton) copyFenButton.disabled = true;
                 if (fastRewindButton) fastRewindButton.disabled = true;
                 if (fastForwardButton) fastForwardButton.disabled = true;
                 if (flipBoardButton) flipBoardButton.disabled = true;
                 if (resumeGameButton) resumeGameButton.disabled = true;
                 inVariationMode = false;
            }
            return data;
        } catch (error) {
            console.error(`Network or other error fetching from ${url}:`, error);
            alert(`Could not connect to the server or an error occurred. Please check the console for details. Error: ${error.message}`);
            if (moveInfoDisplay) moveInfoDisplay.textContent = "Network error or server unavailable.";
            if (playerNamesDisplay) playerNamesDisplay.textContent = "";
            if (nextCriticalButton) nextCriticalButton.disabled = true;
            if (prevMoveButton) prevMoveButton.disabled = true;
            if (nextMoveButton) nextMoveButton.disabled = true;
            if (copyFenButton) copyFenButton.disabled = true;
            if (fastRewindButton) fastRewindButton.disabled = true;
            if (fastForwardButton) fastForwardButton.disabled = true;
            if (flipBoardButton) flipBoardButton.disabled = true;
            if (resumeGameButton) resumeGameButton.disabled = true;
            inVariationMode = false;
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
                if (copyFenButton) copyFenButton.disabled = true;
                if (fastRewindButton) fastRewindButton.disabled = true;
                if (fastForwardButton) fastForwardButton.disabled = true;
                if (flipBoardButton) flipBoardButton.disabled = true;
                if (resumeGameButton) resumeGameButton.disabled = true;
                return;
            }
            const pgnFiles = await response.json();
            if (pgnFiles.length === 0) {
                pgnFileSelect.innerHTML = '<option value="">No PGN files found</option>';
                if (loadPgnButton) loadPgnButton.disabled = true;
                if (nextCriticalButton) nextCriticalButton.disabled = true;
                if (copyFenButton) copyFenButton.disabled = true;
                if (fastRewindButton) fastRewindButton.disabled = true;
                if (fastForwardButton) fastForwardButton.disabled = true;
                if (flipBoardButton) flipBoardButton.disabled = true;
                if (resumeGameButton) resumeGameButton.disabled = true;
                if (moveInfoDisplay) moveInfoDisplay.textContent = "No PGN files found in the configured directory. Check server PGN_DIR.";
            } else {
                pgnFileSelect.innerHTML = '<option value="">-- Select a PGN --</option>'; // Placeholder
                pgnFiles.forEach(file => {
                    const option = document.createElement("option");
                    option.value = file.id;
                    option.textContent = file.name;
                    option.dataset.gameCount = file.game_count; // Store game_count
                    pgnFileSelect.appendChild(option);
                });
                // Initial state: loadPgnButton disabled until a multi-game PGN is selected,
                // or enabled if a single-game PGN is auto-loaded (handled in 'change' event).
                if (loadPgnButton) loadPgnButton.disabled = true;
                if (moveInfoDisplay) moveInfoDisplay.textContent = "Please select a PGN file and load a game.";
            }
        } catch (error) {
            pgnFileSelect.innerHTML = '<option value="">Error loading PGNs</option>';
            console.error("Error fetching PGN file list:", error);
            alert(`Error fetching PGN file list: ${error.message}. Is the server running?`);
            if (loadPgnButton) loadPgnButton.disabled = true;
            if (nextCriticalButton) nextCriticalButton.disabled = true;
            if (copyFenButton) copyFenButton.disabled = true;
            if (fastRewindButton) fastRewindButton.disabled = true;
            if (fastForwardButton) fastForwardButton.disabled = true;
            if (flipBoardButton) flipBoardButton.disabled = true;
            if (resumeGameButton) resumeGameButton.disabled = true;
        }
    }

    // Initial setup
    if (nextCriticalButton) nextCriticalButton.disabled = true; // Initially disabled
    const prevMoveButton = document.getElementById("prev-move");
    const nextMoveButton = document.getElementById("next-move");

    if (prevMoveButton) prevMoveButton.disabled = true;
    if (nextMoveButton) nextMoveButton.disabled = true;
    if (copyFenButton) copyFenButton.disabled = true;
    if (fastRewindButton) fastRewindButton.disabled = true;
    if (fastForwardButton) fastForwardButton.disabled = true;
    if (flipBoardButton) flipBoardButton.disabled = true;
    if (resumeGameButton) resumeGameButton.disabled = true;

    loadPgnFileList(); // Load PGN files on page load
    // Board is not initialized until a game is loaded.
    // Initial message is set within loadPgnFileList or if it fails.

    // Event listeners for controls
    pgnFileSelect?.addEventListener("change", async () => { // Made async for auto-load
        if (board) {
            board.destroy();
            board = null;
        }
        if (playerNamesDisplay) playerNamesDisplay.textContent = ""; // Clear player names when PGN selection changes

        const selectedOption = pgnFileSelect.options[pgnFileSelect.selectedIndex];
        const pgnFileId = selectedOption.value;
        const gameCount = selectedOption.dataset.gameCount ? parseInt(selectedOption.dataset.gameCount, 10) : 0;

        // Disable navigation buttons initially
        if (nextCriticalButton) nextCriticalButton.disabled = true;
        if (prevMoveButton) prevMoveButton.disabled = true;
        if (nextMoveButton) nextMoveButton.disabled = true;
        if (copyFenButton) copyFenButton.disabled = true;
        if (fastRewindButton) fastRewindButton.disabled = true;
        if (fastForwardButton) fastForwardButton.disabled = true;
        if (flipBoardButton) flipBoardButton.disabled = true;
        if (resumeGameButton) resumeGameButton.disabled = true;
        inVariationMode = false; // Reset variation mode


        if (pgnFileId && gameCount > 0) {
            if (gameCount === 1) {
                if (moveInfoDisplay) moveInfoDisplay.textContent = `Loading single game from ${selectedOption.textContent}...`;
                if (loadPgnButton) loadPgnButton.disabled = true;
                // Automatically load the game
                await fetchAndUpdateBoard('/api/load_game', 'POST', { pgn_file_id: pgnFileId });
                // fetchAndUpdateBoard will handle enabling nav buttons if load is successful
            } else { // gameCount > 1
                if (moveInfoDisplay) moveInfoDisplay.textContent = `PGN file selected (${gameCount} games). Click 'Load First Game' to load.`;
                if (loadPgnButton) loadPgnButton.disabled = false; // Enable button for multi-game PGNs
            }
        } else if (pgnFileId && gameCount === 0) {
            if (moveInfoDisplay) moveInfoDisplay.textContent = `Selected PGN file (${selectedOption.textContent}) contains no games.`;
            if (loadPgnButton) loadPgnButton.disabled = true;
        } else { // No PGN file selected (e.g., "-- Select a PGN --")
            if (moveInfoDisplay) moveInfoDisplay.textContent = "Please select a PGN file and load a game.";
            if (loadPgnButton) loadPgnButton.disabled = true;
        }
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
        if (!board) {
            alert("Please load a game first.");
            return;
        }

        if (inVariationMode) {
            console.log("Next move clicked (Variation Mode)");
            currentVariationPly++;
            if (currentVariationPly < currentVariationSANs.length) {
                const nextSan = currentVariationSANs[currentVariationPly];
                try {
                    // Use currentFenInVariation if valid, otherwise fall back to lastKnownServerFEN
                    const fenToUse = currentFenInVariation || lastKnownServerFEN;
                    if (!fenToUse) {
                        console.error("No valid FEN available for variation move");
                        moveInfoDisplay.textContent = "Error: No valid board position available. Resuming main game.";
                        if (resumeGameButton) resumeGameButton.click();
                        return;
                    }

                    // Convert SAN to square coordinates for cm-chessboard
                    const squares = sanToSquares(nextSan, fenToUse);
                    if (squares) {
                        // Use cm-chessboard's movePiece method
                        await board.movePiece(squares.from, squares.to, true); // true for animation

                        // Update the FEN properly - board.getPosition() only returns the board part
                        const boardPosition = board.getPosition();
                        if (currentFenInVariation) {
                            const fenParts = currentFenInVariation.split(' ');
                            fenParts[0] = boardPosition; // Update board part

                            // Determine the correct turn for the move we're about to make
                            // The move we're about to make is at currentVariationPly
                            const turnForMove = currentVariationPly % 2 === 0 ?
                                (learningSide === 'white' ? 'w' : 'b') :
                                (learningSide === 'white' ? 'b' : 'w');
                            fenParts[1] = turnForMove;

                            // Update move counters
                            if (fenParts[1] === 'w') {
                                fenParts[5] = (parseInt(fenParts[5]) + 1).toString(); // Increment fullmove number
                            }
                            currentFenInVariation = fenParts.join(' ');
                        } else {
                            // Fallback
                            const turnForMove = currentVariationPly % 2 === 0 ?
                                (learningSide === 'white' ? 'w' : 'b') :
                                (learningSide === 'white' ? 'b' : 'w');
                            currentFenInVariation = `${boardPosition} ${turnForMove} KQkq - 0 1`;
                        }

                        updateMoveInfoDisplay({ san: nextSan }, true, currentVariationPly);
                        if (nextMoveButton) nextMoveButton.disabled = (currentVariationPly >= currentVariationSANs.length - 1);
                        if (prevMoveButton) prevMoveButton.disabled = true; // Still no prev in variation
                    } else {
                        console.error(`Illegal move in variation: ${nextSan} from FEN: ${fenToUse}`);
                        moveInfoDisplay.textContent = `Error: Illegal move '${nextSan}' in variation. Resuming main game.`;
                        if (resumeGameButton) resumeGameButton.click(); // Attempt to resume main game
                    }
                } catch (e) {
                    console.error(`Error playing variation move ${nextSan}:`, e);
                    moveInfoDisplay.textContent = `Error playing variation move. Resuming main game.`;
                    if (resumeGameButton) resumeGameButton.click();
                }
            } else {
                // End of variation
                moveInfoDisplay.textContent = "End of variation.";
                if (nextMoveButton) nextMoveButton.disabled = true;
            }
        } else { // Main line play
            console.log("Next move clicked (Main Line)");
            await fetchAndUpdateBoard('/game/next_move', 'POST');
        }
    });

    resumeGameButton?.addEventListener("click", async () => {
        if (!inVariationMode) return; // Should not happen if button is managed correctly
        console.log("Resume game clicked");
        inVariationMode = false;
        await fetchAndUpdateBoard('/game/set_move_index', 'POST', { move_index: mainLineMoveIndexAtVariationStart });
        // fetchAndUpdateBoard will handle disabling resumeGameButton and enabling other buttons.
    });

    // Event listener for "Next Critical Moment" button (now "Next Mistake")
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

        if (nextCriticalButton) nextCriticalButton.disabled = true; // Disable button immediately

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
        if (inCriticalMomentChallenge || inVariationMode) {
            console.log("Learning side changed during challenge/variation. Mode cancelled.");
            inCriticalMomentChallenge = false;
            inVariationMode = false;
            if (board) board.disableMoveInput();
            // Fetch current FEN of the main line to reset state before flipping.
            // If mainLineMoveIndexAtVariationStart is set, use it, otherwise current_fen.
            if (mainLineMoveIndexAtVariationStart && !inCriticalMomentChallenge) { // Ensure we are not in prompt
                 fetchAndUpdateBoard('/game/set_move_index', 'POST', { move_index: mainLineMoveIndexAtVariationStart })
                    .then(() => {
                        if (board) { // Board might be re-initialized
                           const newOrientation = learningSide === 'white' ? COLOR.white : COLOR.black;
                           board.setOrientation(newOrientation, true);
                           console.log("Board orientation changed to:", learningSide);
                        }
                         if (nextCriticalButton && board) nextCriticalButton.disabled = false;
                    });
                 return; // Avoid double update/flip
            } else {
                 fetchAndUpdateBoard('/game/current_fen'); // Resets to current main line FEN
            }
        }

        // If a game is loaded and not in variation/challenge, changing learning side should re-enable the next critical button.
        if (board && nextCriticalButton && !inVariationMode && !inCriticalMomentChallenge) {
            nextCriticalButton.disabled = false;
        }
        // Flip board orientation if board exists (and not handled by async above)
        if (board) {
            const newOrientation = learningSide === 'white' ? COLOR.white : COLOR.black;
            board.setOrientation(newOrientation, true); // true for animation
            console.log("Board orientation changed to:", learningSide);
        }
    });

    fastRewindButton?.addEventListener("click", async () => {
        console.log("Fast rewind clicked");
        if (board) {
            await fetchAndUpdateBoard('/game/go_to_start', 'POST');
        } else {
            alert("Please load a game first.");
        }
    });

    fastForwardButton?.addEventListener("click", async () => {
        console.log("Fast forward clicked");
        if (board) {
            await fetchAndUpdateBoard('/game/go_to_end', 'POST');
        } else {
            alert("Please load a game first.");
        }
    });

    flipBoardButton?.addEventListener("click", () => {
        if (!board) {
            alert("Board is not initialized. Load a game first.");
            return;
        }
        learningSide = (learningSide === 'white') ? 'black' : 'white';
        learnSideSelect.value = learningSide; // Update dropdown

        // Manually trigger the change event logic for learnSideSelect
        // to avoid duplicating the board flipping and console logging logic.
        const event = new Event('change');
        learnSideSelect.dispatchEvent(event);

        console.log("Board flipped by button. Learning side now:", learningSide);
    });

    copyFenButton?.addEventListener("click", async () => {
        if (!board) {
            alert("Board is not initialized. Load a game first.");
            return;
        }
        let fenToCopy = null;

        if (inCriticalMomentChallenge && fenAtCriticalPrompt) {
            // User is being prompted for a move at a critical moment.
            // fenAtCriticalPrompt is the FEN of the board state shown.
            fenToCopy = fenAtCriticalPrompt;
            console.log("Copying FEN from critical moment prompt (server-derived):", fenToCopy);
        } else if (inVariationMode && currentFenInVariation) {
            // User is navigating a client-side variation.
            // currentFenInVariation is derived from board.getPosition().
            fenToCopy = currentFenInVariation;
            console.log("Copying FEN from client-side variation:", fenToCopy);
        } else if (lastKnownServerFEN) {
            // Normal main line play, use the last FEN received from the server.
            fenToCopy = lastKnownServerFEN;
            console.log("Copying last known server FEN for main line:", fenToCopy);
        } else {
            // Fallback if none of the above conditions met (should be rare if game is loaded).
            // This might happen if a game is loaded but no FEN was received yet, or state is unusual.
            fenToCopy = board.getPosition(); // Get current FEN from cm-chessboard
            console.warn("Copying FEN using board.getPosition() as fallback:", fenToCopy);
        }

        if (fenToCopy) {
            try {
                await navigator.clipboard.writeText(fenToCopy);
                const feedbackSpan = document.getElementById("copy-fen-feedback");
                if (feedbackSpan) {
                    feedbackSpan.textContent = "Copied!";
                    feedbackSpan.style.opacity = "1";
                    feedbackSpan.style.visibility = "visible";
                    console.log("FEN copied to clipboard:", fenToCopy);
                    setTimeout(() => {
                        feedbackSpan.style.opacity = "0";
                        feedbackSpan.style.visibility = "hidden";
                    }, 1500); // Start hiding after 1.5 seconds
                }
            } catch (err) {
                console.error("Failed to copy FEN to clipboard:", err);
                alert("Failed to copy FEN. See console for details.");
            }
        } else {
            alert("Could not determine FEN to copy for the current board state.");
        }
    });
});
