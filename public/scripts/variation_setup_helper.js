/**
 * Build variation state after a correct critical-moment guess.
 *
 * @param {object} params
 * @param {string} params.userMoveUci - UCI of the user's move
 * @param {string} params.goodMoveUci - UCI of the expected good move
 * @param {string} params.userMoveSan - SAN of the user's move
 * @param {object} params.lastMoveData - Cached server last_move with variation_sans and move_index_of_blunder
 * @param {object} params.validationData - Server validation response
 * @returns {{ currentVariationSANs: string[], variationSANsStartIndex: number, savePayload: object|null }}
 */
export function buildVariationState({ userMoveUci, goodMoveUci, userMoveSan, lastMoveData, validationData }) {
    if (userMoveUci === goodMoveUci && lastMoveData.variation_sans?.length > 0) {
        return {
            currentVariationSANs: lastMoveData.variation_sans,
            variationSANsStartIndex: 0,
            savePayload: null
        };
    }

    if (validationData.variation_sans && validationData.variation_sans.length > 0) {
        const fullVariationForSaving = validationData.variation_sans;
        const moveIndex = lastMoveData.move_index_of_blunder - 1;
        return {
            currentVariationSANs: validationData.variation_sans.slice(1),
            variationSANsStartIndex: 1,
            savePayload: {
                move_index: moveIndex,
                variation_sans: fullVariationForSaving,
                user_move_san: userMoveSan
            }
        };
    }

    return {
        currentVariationSANs: [userMoveSan],
        variationSANsStartIndex: 0,
        savePayload: null
    };
}
