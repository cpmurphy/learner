import { Chessboard, COLOR } from "./3rdparty/cm-chessboard/Chessboard.js";
import { Arrows, ARROW_TYPE } from "./3rdparty/cm-chessboard/extensions/arrows/Arrows.js";
import { PromotionDialog, PROMOTION_DIALOG_RESULT_TYPE } from "./3rdparty/cm-chessboard/extensions/promotion-dialog/PromotionDialog.js";
import { MoveHelper } from './move_helper.js';
import { Chess } from './3rdparty/chess.js/chess.js';
import { variationDisplayArrayIndex, variationNextArrayIndex } from './variation_helper.js';
import { bestMoveHint } from './hint_helper.js';
import { formatMoveInfoText, formatCriticalPromptText } from './move_display_helper.js';
import { buildVariationState } from './variation_setup_helper.js';
import { computeButtonStates, applyButtonStates } from './button_state_helper.js';
import {
    getGameIdFromURL,
    shouldStartCriticalChallenge,
    selectFenToCopy,
    shouldEnableHint,
    shouldShowArrow,
    fenToDisplay
} from './game_utils_helper.js';

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
    const nextCriticalButton = document.getElementById("next-critical");
    const playerNamesDisplay = document.getElementById("player-names-display");
    const copyFenButton = document.getElementById("copy-fen-button");
    const fastRewindButton = document.getElementById("fast-rewind-moves");
    const fastForwardButton = document.getElementById("fast-forward-moves");
    const flipBoardButton = document.getElementById("flip-board");
    const resumeGameButton = document.getElementById("resume-game");
    const hintButton = document.getElementById("hint-button");
    const hintBubble = document.getElementById("hint-bubble");
    const prevMoveButton = document.getElementById("prev-move");
    const nextMoveButton = document.getElementById("next-move");

    const navButtons = {
        nextCritical: nextCriticalButton,
        prevMove: prevMoveButton,
        nextMove: nextMoveButton,
        fastRewind: fastRewindButton,
        fastForward: fastForwardButton,
        resumeGame: resumeGameButton,
        copyFen: copyFenButton,
        flipBoard: flipBoardButton
    };

    function setNavButtonStates(mode, extra = {}) {
        applyButtonStates(navButtons, computeButtonStates({
            mode,
            boardExists: !!board,
            learningSide,
            inVariationMode,
            currentVariationPly,
            variationSANs: currentVariationSANs,
            variationSANsStartIndex,
            ...extra
        }));
    }

    let learningSide = learnSideSelect.value || 'white';
    let inCriticalMomentChallenge = false;
    let fenAtCriticalPrompt = null; // FEN before the bad move, for reverting
    let goodMoveSanForChallenge = null; // SAN of the good alternative move
    let lastKnownServerFEN = null; // Stores the last FEN received from the server for the main line

    let wrongGuessCount = 0;
    let hintShown = false;
    let arrowShown = false;

    function resetHintState() {
        wrongGuessCount = 0;
        hintShown = false;
        arrowShown = false;
        if (hintButton) {
            hintButton.disabled = true;
        }
        if (hintBubble) {
            hintBubble.style.display = 'none';
            hintBubble.textContent = '';
        }
        if (board && board.removeArrows) board.removeArrows();
    }

    // State for variation play
    let inVariationMode = false;
    let mainLineMoveIndexAtVariationStart = 0;
    let variationStartMoveNumber = 0; // Move number where variation starts
    let variationStartTurn = null; // Turn (white/black) when variation starts
    let currentVariationSANs = [];
    let currentVariationPly = 0;
    let variationSANsStartIndex = 0; // Index offset: 0 if user's move is in array, 1 if it was sliced
    let userMoveSanInVariation = null; // Store the user's move for variation navigation
    let currentFenInVariation = null;
    let variationChess = null; // Chess.js instance for variation mode
    let nextMoveInFlight = false;

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

        // Detect pawn promotion: pawn moving to rank 1 or 8 without a promotion piece
        if (!event.promotionPiece && MoveHelper.isPromotionMove(fenAtCriticalPrompt, event.squareFrom, event.squareTo)) {
            const chessForColor = new Chess(fenAtCriticalPrompt);
            const movingPiece = chessForColor.get(event.squareFrom);
            board.showPromotionDialog(event.squareTo, movingPiece.color, async (result) => {
                if (result.type === PROMOTION_DIALOG_RESULT_TYPE.canceled) {
                    board.setPosition(fenAtCriticalPrompt, false);
                    return;
                }
                // result.piece is like 'wq' or 'bq'; extract just the piece type letter
                const promotionPiece = result.piece[1];
                await handleCriticalMoveAttempt({
                    type: 'moveInputFinished',
                    squareFrom: event.squareFrom,
                    squareTo: event.squareTo,
                    promotionPiece: promotionPiece
                });
            });
            return false;
        }

        let userMoveSan;
        try {
            const moveHelper = new MoveHelper(fenAtCriticalPrompt, event.squareFrom, event.squareTo, event.promotionPiece);
            userMoveSan = moveHelper.getSan();

            if (!userMoveSan) {
                // This implies the move was illegal by chess.js in MoveHelper,
                // or some other error occurred (e.g. invalid FEN, missing params).
                // The MoveHelper logs specifics.
                console.error("Critical Challenge - MoveHelper could not produce SAN. Move might be illegal or data inconsistent.",
                              { from: event.squareFrom, to: event.squareTo, promotion: event.promotionPiece, fen: fenAtCriticalPrompt });
                moveInfoDisplay.textContent = "That move is not valid or could not be processed. Try again!";
                // Ensure board is reset to the state before the attempted invalid move.
                if (board && fenAtCriticalPrompt) {
                    board.setPosition(fenAtCriticalPrompt, false); // false for no animation
                }
                return false; // Reject the move.
            }
        } catch (e) {
            // Catch any unexpected errors from MoveHelper instantiation or getSan() itself, though MoveHelper is designed to catch its own errors.
            console.error("Critical Challenge - Error generating SAN using MoveHelper:", e);
            moveInfoDisplay.textContent = "Error processing your move. Try again!";
            // Ensure board is reset if an unexpected error occurs during SAN generation.
            if (board && fenAtCriticalPrompt) {
                board.setPosition(fenAtCriticalPrompt, false); // false for no animation
            }
            return false;
        }

        const userMoveUci = event.squareFrom + event.squareTo + (event.promotionPiece || '');
        console.log(`Critical Challenge - User attempted: ${userMoveSan} (UCI: ${userMoveUci}), Expected good move SAN: ${goodMoveSanForChallenge}`);

        // Convert the good move's SAN to UCI to send to the backend validator
        const tempChess = new Chess(fenAtCriticalPrompt);
        const goodMoveObject = tempChess.move(goodMoveSanForChallenge, { sloppy: true });
        if (!goodMoveObject) {
            console.error(`Could not parse good_move_san from server ('${goodMoveSanForChallenge}') into a move object for FEN: ${fenAtCriticalPrompt}`);
            moveInfoDisplay.textContent = "A data error occurred. Could not validate your move. Resuming game.";
            if (resumeGameButton) resumeGameButton.click(); // Exit challenge gracefully
            return false; // Reject the move
        }
        const goodMoveUci = goodMoveObject.from + goodMoveObject.to + (goodMoveObject.promotion || '');

        try {
            const response = await fetch('/game/validate_critical_move', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    fen: fenAtCriticalPrompt,
                    user_move_uci: userMoveUci,
                    good_move_uci: goodMoveUci
                })
            });
            const validationData = await response.json();

            if (!response.ok) {
                console.error(`Error validating move: ${validationData.error || response.statusText}`);
                moveInfoDisplay.textContent = "Could not validate move due to a server error. Try again!";
                board.setPosition(fenAtCriticalPrompt, false);
                return false;
            }

            if (validationData.good_enough) {
                moveInfoDisplay.textContent = `Correct! "${userMoveSan}" is a good move.`;
                resetHintState();
                const lastMoveDataForVariation = window.lastServerMoveData;

                if (lastMoveDataForVariation) {
                    inVariationMode = true;
                    mainLineMoveIndexAtVariationStart = lastMoveDataForVariation.move_index_of_blunder;

                    // Calculate the starting move number and turn for the variation
                    // The variation replaces the blunder move, which is the next move after lastMoveDataForVariation
                    // The variation starts with learningSide making a move (replacing the blunder move)
                    variationStartTurn = learningSide;

                    // The variation replaces the blunder move, so it starts at the same move number
                    variationStartMoveNumber = lastMoveDataForVariation.number;

                    const variationState = buildVariationState({
                        userMoveUci,
                        goodMoveUci,
                        userMoveSan,
                        lastMoveData: lastMoveDataForVariation,
                        validationData
                    });
                    currentVariationSANs = variationState.currentVariationSANs;
                    variationSANsStartIndex = variationState.variationSANsStartIndex;

                    if (variationState.savePayload) {
                        try {
                            await fetch('/game/add_variation', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify(variationState.savePayload)
                            });
                            await fetch('/game/save', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' }
                            });
                        } catch (error) {
                            console.error('Error saving variation:', error);
                        }
                    }

                    variationChess = new Chess(fenAtCriticalPrompt);
                    variationChess.move(userMoveSan, { sloppy: true }); // Apply the user's validated move
                    currentFenInVariation = variationChess.fen();
                    userMoveSanInVariation = userMoveSan; // Store for backward navigation

                    // Update the board to show the position after the user's move
                    board.setPosition(currentFenInVariation, true); // true for animation

                    // currentVariationPly tracks the number of moves played in the variation
                    // Since we've already applied the user's move, we've played 1 move
                    currentVariationPly = 1; // User just played the first move

                    // Update the display to show the user's move
                    updateMoveInfoDisplay({ san: userMoveSan }, true, currentVariationPly);

                    setNavButtonStates('postCorrectGuess');
                } else {
                    // Fallback: Should not be reached if challenge was correctly initiated.
                    moveInfoDisplay.textContent = `Correct! "${userMoveSan}" is a better move. Main game continues.`;
                }

                board.disableMoveInput();
                inCriticalMomentChallenge = false;
                return true; // Accept the move
            } else {
                wrongGuessCount++;
                moveInfoDisplay.textContent = `"${userMoveSan}" is not the best move. Try again!`;
                board.setPosition(fenAtCriticalPrompt, false);

                if (shouldEnableHint(wrongGuessCount, hintShown) && hintButton) {
                    hintButton.disabled = false;
                }
                if (shouldShowArrow(wrongGuessCount, hintShown, arrowShown) && board.addArrow) {
                    board.addArrow(ARROW_TYPE.default, goodMoveObject.from, goodMoveObject.to);
                    arrowShown = true;
                }
                return false; // Reject the move
            }
        } catch (error) {
            console.error("Error during move validation fetch:", error);
            moveInfoDisplay.textContent = "An error occurred while validating your move. Please try again.";
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
        moveInfoDisplay.textContent = formatMoveInfoText(lastMoveData, learningSide, {
            isVariationMove,
            variationPly,
            variationStartMoveNumber,
            variationStartTurn
        });
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
                setNavButtonStates('error');
                inVariationMode = false;
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
                const setupChallenge = shouldStartCriticalChallenge(lastMoveData, learningSide);

                // Always disable move input before deciding to enable it for a new challenge,
                // or if no challenge is being set up. This prevents "moveInput already enabled" errors.
                if (board) {
                    board.disableMoveInput();
                }

                if (setupChallenge) {
                    inCriticalMomentChallenge = true;
                    fenAtCriticalPrompt = lastMoveData.fen_before_move;
                    goodMoveSanForChallenge = lastMoveData.good_move_san;
                    resetHintState();
                } else {
                    inCriticalMomentChallenge = false;
                }

                // If we successfully set move index (e.g. resuming game), exit variation mode.
                if (url === '/game/set_move_index' || url === '/api/load_game' || url === '/game/go_to_start' || url === '/game/go_to_end') {
                    inVariationMode = false;
                    if (resumeGameButton) resumeGameButton.disabled = true;
                    resetHintState();
                }

                const displayFen = fenToDisplay(setupChallenge, fenAtCriticalPrompt, data.fen);

                if (!board) { // First time board initialization
                    const initialOrientation = learningSide === 'white' ? COLOR.white : COLOR.black;
                    const props = {
                        position: displayFen,
                        assetsUrl: assetsUrl,
                        style: {
                            moveFromMarker: undefined, // Optional: clear markers
                            moveToMarker: undefined,   // Optional: clear markers
                        },
                        orientation: initialOrientation,
                        extensions: [{ class: Arrows }, { class: PromotionDialog }]
                    };
                    board = new Chessboard(boardContainer, props);
                    console.log(`Chessboard initialized. FEN: ${displayFen}, Position index: ${data.move_index}, Total positions: ${data.total_positions}, Orientation: ${learningSide}`);
                    setNavButtonStates('initialLoad', {
                        url,
                        hasInitialCriticalForWhite: data.has_initial_critical_moment_for_white
                    });

                } else { // Board already exists, just updating position
                    board.setPosition(displayFen, true); // true for animation
                    console.log(`Board updated. FEN: ${displayFen}, Position index: ${data.move_index}`);
                }

                if (inVariationMode) {
                    setNavButtonStates('variation');
                } else {
                    setNavButtonStates('main', {
                        moveIndex: data.move_index,
                        totalPositions: data.total_positions,
                        url,
                        serverMessage: data.message || '',
                        hasInitialCriticalForWhite: data.has_initial_critical_moment_for_white
                    });
                }


                if (setupChallenge) {
                    moveInfoDisplay.textContent = formatCriticalPromptText(lastMoveData, learningSide);
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
                 setNavButtonStates('error');
                 inVariationMode = false;
            }
            return data;
        } catch (error) {
            console.error(`Network or other error fetching from ${url}:`, error);
            alert(`Could not connect to the server or an error occurred. Please check the console for details. Error: ${error.message}`);
            if (moveInfoDisplay) moveInfoDisplay.textContent = "Network error or server unavailable.";
            if (playerNamesDisplay) playerNamesDisplay.textContent = "";
            setNavButtonStates('error');
            inVariationMode = false;
            return null;
        }
    }

    /**
     * Load the game automatically from the URL parameter
     */
    async function autoLoadGame() {
        const gameId = getGameIdFromURL(window.location.search);

        if (!gameId) {
            if (moveInfoDisplay) {
                moveInfoDisplay.textContent = "No game specified. Please select a game from the library.";
            }
            return;
        }

        // Use the existing fetchAndUpdateBoard function which handles everything:
        // - Board initialization
        // - Player name display
        // - Move info display
        // - Button state management
        // - Error handling
        await fetchAndUpdateBoard('/api/load_game', 'POST', { pgn_file_id: gameId, game_index: 0 });
    }

    // Initial setup
    setNavButtonStates('error');

    // Auto-load the game from URL parameter
    autoLoadGame();

    // Event listeners for controls

    document.getElementById("prev-move")?.addEventListener("click", async () => {
        if (inVariationMode) {
            console.log("Previous move clicked (Variation Mode)");
            if (currentVariationPly > 1) {
                // Undo the last move in variationChess
                variationChess.undo();
                currentVariationPly--;
                board.setPosition(variationChess.fen(), true);
                // currentVariationPly is now the ply for the move we're displaying (the one we just moved back to)
                const arrayIndex = variationDisplayArrayIndex(currentVariationPly, variationSANsStartIndex);
                if (arrayIndex >= 0 && arrayIndex < currentVariationSANs.length) {
                    updateMoveInfoDisplay({ san: currentVariationSANs[arrayIndex] }, true, currentVariationPly);
                } else if (currentVariationPly === 1 && userMoveSanInVariation) {
                    // We're back at the position after user's move (ply 1)
                    updateMoveInfoDisplay({ san: userMoveSanInVariation }, true, currentVariationPly);
                }
                if (nextMoveButton) nextMoveButton.disabled = false;
            } else if (currentVariationPly === 1 && fenAtCriticalPrompt) {
                console.log("Exiting variation mode, returning to critical moment prompt");

                const positionBeforeBlunder = mainLineMoveIndexAtVariationStart - 1;

                if (positionBeforeBlunder >= 0) {
                    await fetchAndUpdateBoard('/game/set_move_index', 'POST', { move_index: positionBeforeBlunder });
                } else {
                    console.error("Invalid position before blunder:", positionBeforeBlunder);
                    // Fallback: just set the board position and exit variation mode
                    board.setPosition(fenAtCriticalPrompt, true);
                    inVariationMode = false;
                    if (resumeGameButton) resumeGameButton.disabled = true;
                }
            }
            return;
        }
        // Main line play
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
        if (nextMoveInFlight) return;
        nextMoveInFlight = true;
        try {
            if (inVariationMode) {
                console.log("Next move clicked (Variation Mode)");
                const arrayIndex = variationNextArrayIndex(currentVariationPly, variationSANsStartIndex);

                // Check if we've reached the end of the variation
                if (arrayIndex >= currentVariationSANs.length) {
                    // End of variation
                    moveInfoDisplay.textContent = "End of variation. Use Resume Game to return to the main line.";
                    if (nextMoveButton) nextMoveButton.disabled = true;
                    return;
                }

                // Play the next move in variationChess
                const nextSan = currentVariationSANs[arrayIndex];
                try {
                    const moveResult = MoveHelper.sanToSquares(nextSan, variationChess.fen());
                    if (moveResult && moveResult.moves) {
                        for (const move of moveResult.moves) {
                            await board.movePiece(move.from, move.to, true);
                        }
                        if (moveResult.remove) {
                            board.setPiece(moveResult.remove, null);
                        }
                        // Handle pawn promotion - replace the pawn with the promoted piece
                        if (moveResult.promotion && moveResult.promotionSquare) {
                            board.setPiece(moveResult.promotionSquare, moveResult.promotion);
                        }
                        variationChess.move(nextSan, { sloppy: true });
                        currentFenInVariation = variationChess.fen();
                        currentVariationPly++;
                        // currentVariationPly is now the ply for the move we just played
                        updateMoveInfoDisplay({ san: nextSan }, true, currentVariationPly);
                        // Check if we've reached the end
                        if (nextMoveButton) nextMoveButton.disabled = (variationNextArrayIndex(currentVariationPly, variationSANsStartIndex) >= currentVariationSANs.length);
                    } else {
                        console.error(`Illegal move in variation: ${nextSan} from FEN: ${variationChess.fen()}`);
                        moveInfoDisplay.textContent = `Error: Illegal move '${nextSan}' in variation. Resuming main game.`;
                        if (resumeGameButton) resumeGameButton.click();
                    }
                } catch (e) {
                    console.error(`Error playing variation move ${nextSan}:`, e);
                    moveInfoDisplay.textContent = `Error playing variation move. Resuming main game.`;
                    if (resumeGameButton) resumeGameButton.click();
                }
                return;
            }
            if (inCriticalMomentChallenge) {
                // User declined to guess at the critical moment. The board is showing
                // fenAtCriticalPrompt (the position BEFORE the blunder), while the server's
                // index already sits on the blunder move. Reveal ONLY the played (inferior)
                // move — lastKnownServerFEN holds the position right after it — without
                // advancing to the opponent's reply. Exit the challenge so the next click
                // resumes normal main-line navigation (and we never get stuck re-prompting).
                console.log("Next move clicked (declining critical challenge)");
                inCriticalMomentChallenge = false;
                goodMoveSanForChallenge = null;
                resetHintState();
                if (board) {
                    board.disableMoveInput();
                    if (lastKnownServerFEN) board.setPosition(lastKnownServerFEN, true);
                }
                // Show the move that was actually played (the blunder), with its annotation.
                updateMoveInfoDisplay(window.lastServerMoveData);
                setNavButtonStates('declineCritical');
                return;
            }
            // Main line play
            console.log("Next move clicked (Main Line)");
            await fetchAndUpdateBoard('/game/next_move', 'POST');
        } finally {
            nextMoveInFlight = false;
        }
    });

    hintButton?.addEventListener("click", () => {
        if (!fenAtCriticalPrompt || !goodMoveSanForChallenge) return;
        const hintText = bestMoveHint(fenAtCriticalPrompt, goodMoveSanForChallenge);
        if (!hintText) {
            console.warn("Hint could not be generated for", { fenAtCriticalPrompt, goodMoveSanForChallenge });
            return;
        }
        if (hintBubble) {
            hintBubble.textContent = hintText;
            hintBubble.style.display = 'block';
            const buttonRect = hintButton.getBoundingClientRect();
            const bubbleRect = hintBubble.getBoundingClientRect();
            const buttonCenterX = buttonRect.left + buttonRect.width / 2;
            const arrowX = buttonCenterX - bubbleRect.left;
            const clampedArrowX = Math.max(12, Math.min(bubbleRect.width - 12, arrowX));
            hintBubble.style.setProperty('--arrow-x', `${clampedArrowX}px`);
        }
        hintShown = true;
        hintButton.disabled = true;
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
        resetHintState();
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
        const fenToCopy = selectFenToCopy({
            inCriticalMomentChallenge,
            fenAtCriticalPrompt,
            inVariationMode,
            currentFenInVariation,
            lastKnownServerFEN,
            boardFen: board.getPosition()
        });

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
