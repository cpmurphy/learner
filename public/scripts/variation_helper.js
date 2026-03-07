/**
 * Pure calculation functions for variation mode navigation and display.
 */

/**
 * Calculate the move number for a given ply in a variation.
 *
 * When starting with White: W(1)=start, B(2)=start, W(3)=start+1, B(4)=start+1, ...
 * When starting with Black: B(1)=start, W(2)=start+1, B(3)=start+1, W(4)=start+2, ...
 *
 * @param {number} startMoveNumber - The move number where the variation begins.
 * @param {string} startTurn - 'white' or 'black', the side that plays first in the variation.
 * @param {number} variationPly - 1-based ply within the variation (1 = first move).
 * @returns {number} The chess move number for this ply.
 */
export function variationMoveNumber(startMoveNumber, startTurn, variationPly) {
    if (startTurn === 'white') {
        return startMoveNumber + Math.floor((variationPly - 1) / 2);
    }
    return startMoveNumber + Math.floor(variationPly / 2);
}

/**
 * Determine the turn (white/black) for a given ply in a variation.
 *
 * @param {string} startTurn - 'white' or 'black', the side that plays first in the variation.
 * @param {number} variationPly - 1-based ply within the variation.
 * @returns {string} 'white' or 'black'
 */
export function variationTurn(startTurn, variationPly) {
    const isWhiteMove = (startTurn === 'white' && (variationPly - 1) % 2 === 0) ||
                        (startTurn === 'black' && (variationPly - 1) % 2 === 1);
    return isWhiteMove ? 'white' : 'black';
}

/**
 * Calculate the array index into currentVariationSANs for the move displayed at a given ply.
 * This is used when navigating backward to show the correct move SAN.
 *
 * @param {number} currentVariationPly - The ply we are currently displaying (1-based).
 * @param {number} variationSANsStartIndex - 0 if user's move is in the array, 1 if it was sliced off.
 * @returns {number} The array index, or -1 if the ply refers to the user's move that was sliced off.
 */
export function variationDisplayArrayIndex(currentVariationPly, variationSANsStartIndex) {
    return currentVariationPly - 1 - variationSANsStartIndex;
}

/**
 * Calculate the array index for the next move to play from the current ply.
 * This is used by the forward navigation to find which SAN to play next.
 *
 * @param {number} currentVariationPly - The current ply (1-based, number of moves already played).
 * @param {number} variationSANsStartIndex - 0 if user's move is in the array, 1 if it was sliced off.
 * @returns {number} The array index of the next move to play.
 */
export function variationNextArrayIndex(currentVariationPly, variationSANsStartIndex) {
    return currentVariationPly - variationSANsStartIndex;
}
