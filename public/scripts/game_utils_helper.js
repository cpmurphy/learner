/**
 * Small pure utilities extracted from main.js game UI logic.
 */

/**
 * Extract game ID from URL search string.
 * @param {string} search - window.location.search or equivalent
 * @returns {string|null}
 */
export function getGameIdFromURL(search) {
    const params = new URLSearchParams(search);
    return params.get('id');
}

/**
 * Determine whether a critical moment challenge should start.
 * @param {object|null} lastMoveData
 * @param {string} learningSide - 'white' or 'black'
 * @returns {boolean}
 */
export function shouldStartCriticalChallenge(lastMoveData, learningSide) {
    return !!(lastMoveData &&
        lastMoveData.is_critical &&
        lastMoveData.turn === learningSide &&
        lastMoveData.good_move_san &&
        lastMoveData.fen_before_move);
}

/**
 * Select which FEN to copy based on current UI mode.
 * @param {object} params
 * @param {boolean} params.inCriticalMomentChallenge
 * @param {string|null} params.fenAtCriticalPrompt
 * @param {boolean} params.inVariationMode
 * @param {string|null} params.currentFenInVariation
 * @param {string|null} params.lastKnownServerFEN
 * @param {string|null} [params.boardFen] - Fallback from board.getPosition()
 * @returns {string|null}
 */
export function selectFenToCopy({
    inCriticalMomentChallenge,
    fenAtCriticalPrompt,
    inVariationMode,
    currentFenInVariation,
    lastKnownServerFEN,
    boardFen = null
}) {
    if (inCriticalMomentChallenge && fenAtCriticalPrompt) {
        return fenAtCriticalPrompt;
    }
    if (inVariationMode && currentFenInVariation) {
        return currentFenInVariation;
    }
    if (lastKnownServerFEN) {
        return lastKnownServerFEN;
    }
    return boardFen;
}

/**
 * Whether the hint button should be enabled after wrong guesses.
 * @param {number} wrongGuessCount
 * @param {boolean} hintShown
 * @returns {boolean}
 */
export function shouldEnableHint(wrongGuessCount, hintShown) {
    return !hintShown && wrongGuessCount >= 3;
}

/**
 * Whether the best-move arrow should be shown after wrong guesses.
 * @param {number} wrongGuessCount
 * @param {boolean} hintShown
 * @param {boolean} arrowShown
 * @returns {boolean}
 */
export function shouldShowArrow(wrongGuessCount, hintShown, arrowShown) {
    return hintShown && wrongGuessCount >= 6 && !arrowShown;
}

/**
 * FEN to display on the board after a server response.
 * @param {boolean} setupChallenge
 * @param {string|null} fenAtCriticalPrompt
 * @param {string|null} serverFen
 * @returns {string|null}
 */
export function fenToDisplay(setupChallenge, fenAtCriticalPrompt, serverFen) {
    return setupChallenge ? fenAtCriticalPrompt : serverFen;
}
