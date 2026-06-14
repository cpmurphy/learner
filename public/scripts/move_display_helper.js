import { variationMoveNumber, variationTurn } from './variation_helper.js';

/**
 * Owns the move-info display element and its formatting context.
 */
export class MoveInfoDisplay {
    constructor(element, getLearningSide) {
        this.element = element;
        this.getLearningSide = getLearningSide;
        this.variation = null;
    }

    setVariation(variation) {
        this.variation = variation;
    }

    showMain(lastMoveData) {
        this.setText(formatMoveInfoText(lastMoveData, this.getLearningSide()));
    }

    showVariation(san, variationPly = null) {
        if (!this.variation) return;
        const ply = variationPly ?? this.variation.currentPly;
        this.setText(formatVariationMoveText(
            san,
            this.variation.startMoveNumber,
            this.variation.startTurn,
            ply
        ));
    }

    showCriticalPrompt(lastMoveData) {
        this.setText(formatCriticalPromptText(lastMoveData, this.getLearningSide()));
    }

    showMessage(message) {
        this.setText(message);
    }

    setText(text) {
        if (this.element) this.element.textContent = text;
    }
}

/**
 * Format the move-info text for a main-line move.
 * @param {object} lastMoveData - Server last_move object with number, turn, san, etc.
 * @param {string} learningSide - 'white' or 'black'
 * @returns {string}
 */
export function formatMainLineMoveText(lastMoveData, learningSide) {
    const movePrefix = `${lastMoveData.number}${lastMoveData.turn === 'white' ? '.' : '...'}`;
    let displayText = `${movePrefix} ${lastMoveData.san}`;

    if (lastMoveData.centipawn_loss !== null && lastMoveData.centipawn_loss !== undefined && lastMoveData.centipawn_loss > 0) {
        displayText += lastMoveData.centipawn_loss > 100 ? ` ??` : ` ?`;
    }

    if (lastMoveData.turn === learningSide && lastMoveData.comment && lastMoveData.comment.trim() !== '' && !/cp_loss:/.test(lastMoveData.comment)) {
        displayText += ` {${lastMoveData.comment.trim()}}`;
    }

    return displayText;
}

/**
 * Format the move-info text for a variation move.
 * @param {string} san - SAN of the move in the variation
 * @param {number} variationStartMoveNumber - Move number where variation begins
 * @param {string} variationStartTurn - 'white' or 'black'
 * @param {number} variationPly - 1-based ply within the variation
 * @returns {string}
 */
export function formatVariationMoveText(san, variationStartMoveNumber, variationStartTurn, variationPly) {
    const turnInVariation = variationTurn(variationStartTurn, variationPly);
    const moveNumberInVariation = variationMoveNumber(variationStartMoveNumber, variationStartTurn, variationPly);
    const movePrefix = `${moveNumberInVariation}${turnInVariation === 'white' ? '.' : '...'}`;
    return `Variation: ${movePrefix} ${san}`;
}

/**
 * Format the prompt shown when a critical moment challenge starts.
 * @param {object} lastMoveData - Server last_move object
 * @param {string} learningSide - 'white' or 'black'
 * @returns {string}
 */
export function formatCriticalPromptText(lastMoveData, learningSide) {
    const movePrefix = `${lastMoveData.number}${lastMoveData.turn === 'white' ? '.' : '...'}`;
    return `${movePrefix}${lastMoveData.san} played. Try a better move for ${learningSide}.`;
}

/**
 * Format move-info display text for any context (main line, variation, or game start).
 * @param {object|null} lastMoveData - Move data or null for game start
 * @param {string} learningSide - 'white' or 'black'
 * @param {object} options
 * @returns {string}
 */
export function formatMoveInfoText(lastMoveData, learningSide, options = {}) {
    const {
        isVariationMove = false,
        variationPly = 0,
        variationStartMoveNumber,
        variationStartTurn
    } = options;

    if (isVariationMove && lastMoveData && lastMoveData.san) {
        return formatVariationMoveText(
            lastMoveData.san,
            variationStartMoveNumber,
            variationStartTurn,
            variationPly
        );
    }
    if (lastMoveData) {
        return formatMainLineMoveText(lastMoveData, learningSide);
    }
    return 'Game start.';
}
