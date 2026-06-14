import { Chessboard, COLOR } from "./3rdparty/cm-chessboard/Chessboard.js";
import { Arrows, ARROW_TYPE } from "./3rdparty/cm-chessboard/extensions/arrows/Arrows.js";
import { PromotionDialog, PROMOTION_DIALOG_RESULT_TYPE } from "./3rdparty/cm-chessboard/extensions/promotion-dialog/PromotionDialog.js";
import { MoveHelper } from './move_helper.js';
import { Chess } from './3rdparty/chess.js/chess.js';
import { MoveInfoDisplay } from './move_display_helper.js';
import { NavigationControls } from './button_state_helper.js';
import { CriticalChallenge, getGameIdFromURL } from './game_utils_helper.js';
import { HintState } from './hint_state_helper.js';
import { VariationSession } from './variation_session.js';

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

    let learningSide = learnSideSelect.value || 'white';
    let lastKnownServerFEN = null; // Stores the last FEN received from the server for the main line
    let nextMoveInFlight = false;

    const challenge = new CriticalChallenge();
    const variation = new VariationSession();
    const hints = new HintState({ button: hintButton, bubble: hintBubble, arrowType: ARROW_TYPE.default });
    const moveInfo = new MoveInfoDisplay(moveInfoDisplay, () => learningSide);
    const navigation = new NavigationControls(navButtons);
    moveInfo.setVariation(variation);

    function setNavButtonStates(mode, extra = {}) {
        navigation.setBoardExists(!!board);
        navigation.setLearningSide(learningSide);
        if (mode === 'error') navigation.setError();
        if (mode === 'declineCritical') navigation.setDeclineCritical();
        if (mode === 'initialLoad') navigation.setInitialLoad(extra);
        if (mode === 'variation') navigation.setVariation(variation);
        if (mode === 'postCorrectGuess') navigation.setPostCorrectGuess(variation);
        if (mode === 'main') {
            navigation.setMain(
                { moveIndex: extra.moveIndex, totalPositions: extra.totalPositions },
                {
                    url: extra.url,
                    serverMessage: extra.serverMessage,
                    hasInitialCriticalForWhite: extra.hasInitialCriticalForWhite
                }
            );
        }
    }

    function resetHintState() {
        hints.reset(board);
    }

    function fenToCopy() {
        return challenge.fenToCopy() || variation.currentFen || lastKnownServerFEN || board.getPosition();
    }


    /**
     * Handles the user's move attempt during a critical moment challenge.
     * This function is passed to `board.enableMoveInput`.
     * @param {object} event - The event object from cm-chessboard, contains `squareFrom`, `squareTo`, `piece`.
     * @returns {boolean} - True if the move is allowed (correct), false otherwise.
     */
    async function handleCriticalMoveAttempt(event) {
        if (event.type !== 'moveInputFinished') {
            return;
        }

        if (!challenge.active || !challenge.goodMoveSan) {
            console.warn("handleCriticalMoveAttempt called inappropriately.");
            return false;
        }

        const fenAtPrompt = challenge.fenAtPrompt;
        const goodMoveSan = challenge.goodMoveSan;

        if (!event.promotionPiece && MoveHelper.isPromotionMove(fenAtPrompt, event.squareFrom, event.squareTo)) {
            const chessForColor = new Chess(fenAtPrompt);
            const movingPiece = chessForColor.get(event.squareFrom);
            board.showPromotionDialog(event.squareTo, movingPiece.color, async (result) => {
                if (result.type === PROMOTION_DIALOG_RESULT_TYPE.canceled) {
                    board.setPosition(fenAtPrompt, false);
                    return;
                }
                await handleCriticalMoveAttempt({
                    type: 'moveInputFinished',
                    squareFrom: event.squareFrom,
                    squareTo: event.squareTo,
                    promotionPiece: result.piece[1]
                });
            });
            return false;
        }

        let userMoveSan;
        try {
            const moveHelper = new MoveHelper(fenAtPrompt, event.squareFrom, event.squareTo, event.promotionPiece);
            userMoveSan = moveHelper.getSan();
            if (!userMoveSan) {
                console.error("Critical Challenge - MoveHelper could not produce SAN. Move might be illegal or data inconsistent.",
                              { from: event.squareFrom, to: event.squareTo, promotion: event.promotionPiece, fen: fenAtPrompt });
                moveInfo.showMessage("That move is not valid or could not be processed. Try again!");
                board?.setPosition(fenAtPrompt, false);
                return false;
            }
        } catch (e) {
            console.error("Critical Challenge - Error generating SAN using MoveHelper:", e);
            moveInfo.showMessage("Error processing your move. Try again!");
            board?.setPosition(fenAtPrompt, false);
            return false;
        }

        const userMoveUci = event.squareFrom + event.squareTo + (event.promotionPiece || '');
        console.log(`Critical Challenge - User attempted: ${userMoveSan} (UCI: ${userMoveUci}), Expected good move SAN: ${goodMoveSan}`);

        const tempChess = new Chess(fenAtPrompt);
        const goodMoveObject = tempChess.move(goodMoveSan, { sloppy: true });
        if (!goodMoveObject) {
            console.error(`Could not parse good_move_san from server ('${goodMoveSan}') into a move object for FEN: ${fenAtPrompt}`);
            moveInfo.showMessage("A data error occurred. Could not validate your move. Resuming game.");
            resumeGameButton?.click();
            return false;
        }
        const goodMoveUci = goodMoveObject.from + goodMoveObject.to + (goodMoveObject.promotion || '');

        try {
            const response = await fetch('/game/validate_critical_move', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    fen: fenAtPrompt,
                    user_move_uci: userMoveUci,
                    good_move_uci: goodMoveUci
                })
            });
            const validationData = await response.json();

            if (!response.ok) {
                console.error(`Error validating move: ${validationData.error || response.statusText}`);
                moveInfo.showMessage("Could not validate move due to a server error. Try again!");
                board.setPosition(fenAtPrompt, false);
                return false;
            }

            if (validationData.good_enough) {
                moveInfo.showMessage(`Correct! "${userMoveSan}" is a good move.`);
                hints.reset(board);
                const lastMoveDataForVariation = window.lastServerMoveData;

                if (lastMoveDataForVariation) {
                    const variationPlan = variation.start({
                        moveAttempt: { userMoveUci, goodMoveUci, userMoveSan },
                        lastMoveData: lastMoveDataForVariation,
                        validationData,
                        fenAtPrompt,
                        learningSide
                    });

                    if (variationPlan.savePayload) {
                        try {
                            await fetch('/game/add_variation', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify(variationPlan.savePayload)
                            });
                            await fetch('/game/save', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' }
                            });
                        } catch (error) {
                            console.error('Error saving variation:', error);
                        }
                    }

                    board.setPosition(variation.currentFen, true);
                    moveInfo.showVariation(userMoveSan, variation.currentPly);
                    setNavButtonStates('postCorrectGuess');
                } else {
                    moveInfo.showMessage(`Correct! "${userMoveSan}" is a better move. Main game continues.`);
                }

                board.disableMoveInput();
                challenge.stop();
                return true;
            }

            moveInfo.showMessage(`"${userMoveSan}" is not the best move. Try again!`);
            board.setPosition(fenAtPrompt, false);
            hints.recordWrongGuess(board, goodMoveObject);
            return false;
        } catch (error) {
            console.error("Error during move validation fetch:", error);
            moveInfo.showMessage("An error occurred while validating your move. Please try again.");
            board.setPosition(fenAtPrompt, false);
            return false;
        }
    }

    /**
     * Updates the move information display area.
     * @param {object|null} lastMoveData - Data about the last move, or null.
     */
    function updateMoveInfoDisplay(lastMoveData, isVariationMove = false, variationPly = 0) {
        if (isVariationMove && lastMoveData?.san) {
            moveInfo.showVariation(lastMoveData.san, variationPly);
            return;
        }
        moveInfo.showMain(lastMoveData);
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
                moveInfo.showMessage(`Error: ${errorMsg}`);
                if (playerNamesDisplay) playerNamesDisplay.textContent = "";

                if (errorMsg.includes("No game loaded")) {
                     if (url === '/game/current_fen' && !board) {
                        moveInfo.showMessage("Please select a PGN file and load a game.");
                     }
                } else if (errorMsg.includes("PGN_DIR environment variable not set") || errorMsg.includes("PGN directory not found")) {
                    alert("Server PGN directory not configured. Please check server logs.");
                } else if (url === '/api/load_game') {
                    alert(`Error loading game: ${errorMsg}`);
                }
                // Disable all navigation buttons on error
                setNavButtonStates('error');
                variation.reset();
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
                const setupChallenge = challenge.prepare(lastMoveData, learningSide);

                // Always disable move input before deciding to enable it for a new challenge,
                // or if no challenge is being set up. This prevents "moveInput already enabled" errors.
                if (board) {
                    board.disableMoveInput();
                }

                if (setupChallenge) {
                    resetHintState();
                }

                // If we successfully set move index (e.g. resuming game), exit variation mode.
                if (url === '/game/set_move_index' || url === '/api/load_game' || url === '/game/go_to_start' || url === '/game/go_to_end') {
                    variation.reset();
                    if (resumeGameButton) resumeGameButton.disabled = true;
                    resetHintState();
                }

                const displayFen = challenge.displayFen(data.fen);

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

                if (variation.active) {
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
                    moveInfo.showCriticalPrompt(lastMoveData);
                    board.enableMoveInput(handleCriticalMoveAttempt, learningSide);
                } else if (!variation.active) { // Don't update with main line move if we just entered variation
                    updateMoveInfoDisplay(lastMoveData);
                }
                // If in variation mode, move info is updated by "Next Move" (variation) handler.

                if (data.message) {
                    console.log(`Server message: ${data.message}`);
                }

            } else if (data.error) {
                 console.error("Error from server:", data.error);
                 moveInfo.showMessage(data.error || "An unspecified error occurred.");
                 if (playerNamesDisplay) playerNamesDisplay.textContent = "";
                 setNavButtonStates('error');
                 variation.reset();
            }
            return data;
        } catch (error) {
            console.error(`Network or other error fetching from ${url}:`, error);
            alert(`Could not connect to the server or an error occurred. Please check the console for details. Error: ${error.message}`);
            moveInfo.showMessage("Network error or server unavailable.");
            if (playerNamesDisplay) playerNamesDisplay.textContent = "";
            setNavButtonStates('error');
            variation.reset();
            return null;
        }
    }

    /**
     * Load the game automatically from the URL parameter
     */
    async function autoLoadGame() {
        const gameId = getGameIdFromURL(window.location.search);

        if (!gameId) {
            moveInfo.showMessage("No game specified. Please select a game from the library.");
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
        if (variation.active) {
            console.log("Previous move clicked (Variation Mode)");
            if (variation.undo()) {
                board.setPosition(variation.currentFen, true);
                const san = variation.displayedSan();
                if (san) moveInfo.showVariation(san, variation.currentPly);
                if (nextMoveButton) nextMoveButton.disabled = false;
            } else if (variation.currentPly === 1) {
                console.log("Exiting variation mode, returning to critical moment prompt");
                const positionBeforeBlunder = variation.positionBeforeBlunder();

                if (positionBeforeBlunder >= 0) {
                    await fetchAndUpdateBoard('/game/set_move_index', 'POST', { move_index: positionBeforeBlunder });
                } else {
                    console.error("Invalid position before blunder:", positionBeforeBlunder);
                    board.setPosition(variation.fenAtPrompt, true);
                    variation.reset();
                    if (resumeGameButton) resumeGameButton.disabled = true;
                }
            }
            return;
        }

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
            if (variation.active) {
                console.log("Next move clicked (Variation Mode)");
                if (!variation.canAdvance()) {
                    moveInfo.showMessage("End of variation. Use Resume Game to return to the main line.");
                    if (nextMoveButton) nextMoveButton.disabled = true;
                    return;
                }

                const nextSan = variation.nextSan();
                try {
                    const moveResult = MoveHelper.sanToSquares(nextSan, variation.currentFen);
                    if (moveResult && moveResult.moves) {
                        for (const move of moveResult.moves) {
                            await board.movePiece(move.from, move.to, true);
                        }
                        if (moveResult.remove) {
                            board.setPiece(moveResult.remove, null);
                        }
                        if (moveResult.promotion && moveResult.promotionSquare) {
                            board.setPiece(moveResult.promotionSquare, moveResult.promotion);
                        }
                        variation.applySan(nextSan);
                        moveInfo.showVariation(nextSan, variation.currentPly);
                        if (nextMoveButton) nextMoveButton.disabled = !variation.canAdvance();
                    } else {
                        console.error(`Illegal move in variation: ${nextSan} from FEN: ${variation.currentFen}`);
                        moveInfo.showMessage(`Error: Illegal move '${nextSan}' in variation. Resuming main game.`);
                        resumeGameButton?.click();
                    }
                } catch (e) {
                    console.error(`Error playing variation move ${nextSan}:`, e);
                    moveInfo.showMessage("Error playing variation move. Resuming main game.");
                    resumeGameButton?.click();
                }
                return;
            }
            if (challenge.active) {
                console.log("Next move clicked (declining critical challenge)");
                challenge.stop();
                resetHintState();
                if (board) {
                    board.disableMoveInput();
                    if (lastKnownServerFEN) board.setPosition(lastKnownServerFEN, true);
                }
                updateMoveInfoDisplay(window.lastServerMoveData);
                setNavButtonStates('declineCritical');
                return;
            }

            console.log("Next move clicked (Main Line)");
            await fetchAndUpdateBoard('/game/next_move', 'POST');
        } finally {
            nextMoveInFlight = false;
        }
    });

    hintButton?.addEventListener("click", () => {
        if (!challenge.fenAtPrompt || !challenge.goodMoveSan) return;
        const hintText = hints.show(challenge.fenAtPrompt, challenge.goodMoveSan);
        if (!hintText) {
            console.warn("Hint could not be generated for", {
                fenAtCriticalPrompt: challenge.fenAtPrompt,
                goodMoveSanForChallenge: challenge.goodMoveSan
            });
        }
    });

    resumeGameButton?.addEventListener("click", async () => {
        if (!variation.active) return; // Should not happen if button is managed correctly
        console.log("Resume game clicked");
        const moveIndex = variation.mainLineMoveIndex;
        variation.reset();
        await fetchAndUpdateBoard('/game/set_move_index', 'POST', { move_index: moveIndex });
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
        navigation.setLearningSide(learningSide);
        console.log("Learning side changed to:", learningSide);
        resetHintState();
        if (challenge.active || variation.active) {
            console.log("Learning side changed during challenge/variation. Mode cancelled.");
            challenge.stop();
            const variationMoveIndex = variation.mainLineMoveIndex;
            variation.reset();
            if (board) board.disableMoveInput();

            if (variationMoveIndex) {
                 fetchAndUpdateBoard('/game/set_move_index', 'POST', { move_index: variationMoveIndex })
                    .then(() => {
                        if (board) {
                           const newOrientation = learningSide === 'white' ? COLOR.white : COLOR.black;
                           board.setOrientation(newOrientation, true);
                           console.log("Board orientation changed to:", learningSide);
                        }
                         if (nextCriticalButton && board) nextCriticalButton.disabled = false;
                    });
                 return;
            }
            fetchAndUpdateBoard('/game/current_fen');
        }

        if (board && nextCriticalButton && !variation.active && !challenge.active) {
            nextCriticalButton.disabled = false;
        }
        if (board) {
            const newOrientation = learningSide === 'white' ? COLOR.white : COLOR.black;
            board.setOrientation(newOrientation, true);
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
        const fen = fenToCopy();

        if (fen) {
            try {
                await navigator.clipboard.writeText(fen);
                const feedbackSpan = document.getElementById("copy-fen-feedback");
                if (feedbackSpan) {
                    feedbackSpan.textContent = "Copied!";
                    feedbackSpan.style.opacity = "1";
                    feedbackSpan.style.visibility = "visible";
                    console.log("FEN copied to clipboard:", fen);
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
