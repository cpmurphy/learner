/**
 * Build the SAN list and optional save payload for a correct critical-moment guess.
 */
export function buildVariationState(moveAttempt, source) {
    const userMoveUci = moveAttempt.userMoveUci;
    const goodMoveUci = moveAttempt.goodMoveUci;
    const userMoveSan = moveAttempt.userMoveSan;
    const lastMoveData = source.lastMoveData;
    const validationData = source.validationData || {};

    if (userMoveUci === goodMoveUci && lastMoveData.variation_sans?.length > 0) {
        return {
            sans: lastMoveData.variation_sans,
            startIndex: 0,
            savePayload: null
        };
    }

    if (validationData.variation_sans && validationData.variation_sans.length > 0) {
        const fullVariationForSaving = validationData.variation_sans;
        const moveIndex = lastMoveData.move_index_of_blunder - 1;
        return {
            sans: validationData.variation_sans.slice(1),
            startIndex: 1,
            savePayload: {
                move_index: moveIndex,
                variation_sans: fullVariationForSaving,
                user_move_san: userMoveSan
            }
        };
    }

    return {
        sans: [userMoveSan],
        startIndex: 0,
        savePayload: null
    };
}
