import { variationNextArrayIndex } from './variation_helper.js';

/**
 * Compute disabled state for navigation buttons.
 * Returns true for disabled, false for enabled (matches HTML disabled attribute).
 *
 * @param {object} params
 * @param {'main'|'variation'|'declineCritical'|'initialLoad'|'error'} params.mode
 * @param {boolean} [params.boardExists=false]
 * @param {number} [params.moveIndex=0]
 * @param {number} [params.totalPositions=1]
 * @param {number} [params.currentVariationPly=0]
 * @param {string[]} [params.variationSANs=[]]
 * @param {number} [params.variationSANsStartIndex=0]
 * @param {string} [params.learningSide='white']
 * @param {string} [params.url='']
 * @param {string} [params.serverMessage='']
 * @param {boolean} [params.hasInitialCriticalForWhite=false]
 * @param {boolean} [params.inVariationMode=false]
 * @returns {object} Map of button names to disabled boolean
 */
export function computeButtonStates({
    mode,
    boardExists = false,
    moveIndex = 0,
    totalPositions = 1,
    currentVariationPly = 0,
    variationSANs = [],
    variationSANsStartIndex = 0,
    learningSide = 'white',
    url = '',
    serverMessage = '',
    hasInitialCriticalForWhite = false,
    inVariationMode = false
}) {
    if (mode === 'error') {
        return allDisabled();
    }

    if (mode === 'declineCritical') {
        return {
            nextCritical: false,
            prevMove: false,
            nextMove: false,
            fastRewind: false,
            fastForward: false,
            resumeGame: true,
            copyFen: false,
            flipBoard: false
        };
    }

    if (mode === 'initialLoad') {
        const nextCriticalDisabled = !(hasInitialCriticalForWhite && learningSide === 'white');
        return {
            nextCritical: nextCriticalDisabled,
            prevMove: false,
            nextMove: false,
            fastRewind: !inVariationMode,
            fastForward: !inVariationMode,
            resumeGame: !inVariationMode,
            copyFen: false,
            flipBoard: false
        };
    }

    if (mode === 'variation') {
        const nextMoveDisabled = currentVariationPly >= variationSANs.length - 1;
        return {
            nextCritical: true,
            prevMove: undefined,
            nextMove: nextMoveDisabled,
            fastRewind: true,
            fastForward: true,
            resumeGame: false,
            copyFen: !boardExists,
            flipBoard: !boardExists
        };
    }

    if (mode === 'postCorrectGuess') {
        const nextMoveDisabled = variationNextArrayIndex(currentVariationPly, variationSANsStartIndex) >= variationSANs.length;
        return {
            nextCritical: true,
            prevMove: undefined,
            nextMove: nextMoveDisabled,
            fastRewind: undefined,
            fastForward: undefined,
            resumeGame: false,
            copyFen: undefined,
            flipBoard: undefined
        };
    }

    // mode === 'main'
    const noMoreCriticals = url === '/game/next_critical_moment' &&
        serverMessage.startsWith('No further critical moments found');
    let nextCriticalDisabled;
    if (url === '/api/load_game') {
        nextCriticalDisabled = !(hasInitialCriticalForWhite && learningSide === 'white');
    } else {
        nextCriticalDisabled = noMoreCriticals;
    }

    return {
        nextCritical: nextCriticalDisabled,
        prevMove: undefined,
        nextMove: moveIndex >= totalPositions - 1,
        fastRewind: moveIndex === 0,
        fastForward: moveIndex >= totalPositions - 1,
        resumeGame: true,
        copyFen: !boardExists,
        flipBoard: !boardExists
    };
}

function allDisabled() {
    return {
        nextCritical: true,
        prevMove: true,
        nextMove: true,
        fastRewind: true,
        fastForward: true,
        resumeGame: true,
        copyFen: true,
        flipBoard: true
    };
}

/**
 * Apply computed button states to DOM button elements.
 * Skips buttons where state is undefined (unchanged).
 *
 * @param {object} buttons - Map of button name to DOM element (may be null)
 * @param {object} states - Map of button name to disabled boolean
 */
export function applyButtonStates(buttons, states) {
    for (const [name, disabled] of Object.entries(states)) {
        if (disabled === undefined) continue;
        const element = buttons[name];
        if (element) element.disabled = disabled;
    }
}
