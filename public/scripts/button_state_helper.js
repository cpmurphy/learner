import { variationNextArrayIndex } from './variation_helper.js';

const ALL_BUTTONS = [
    'nextCritical',
    'prevMove',
    'nextMove',
    'fastRewind',
    'fastForward',
    'resumeGame',
    'copyFen',
    'flipBoard'
];

/**
 * Owns navigation button state for the game UI.
 */
export class NavigationControls {
    constructor(buttons = {}) {
        this.buttons = buttons;
        this.boardExists = false;
        this.learningSide = 'white';
    }

    setBoardExists(boardExists) {
        this.boardExists = !!boardExists;
    }

    setLearningSide(learningSide) {
        this.learningSide = learningSide || 'white';
    }

    setError() {
        this.apply(allDisabled());
    }

    setDeclineCritical() {
        this.apply({
            nextCritical: false,
            prevMove: false,
            nextMove: false,
            fastRewind: false,
            fastForward: false,
            resumeGame: true,
            copyFen: false,
            flipBoard: false
        });
    }

    setInitialLoad(options = {}) {
        const hasInitialCriticalForWhite = !!options.hasInitialCriticalForWhite;
        const inVariationMode = !!options.inVariationMode;
        this.apply({
            nextCritical: !(hasInitialCriticalForWhite && this.learningSide === 'white'),
            prevMove: false,
            nextMove: false,
            fastRewind: !inVariationMode,
            fastForward: !inVariationMode,
            resumeGame: !inVariationMode,
            copyFen: false,
            flipBoard: false
        });
    }

    setVariation(variation) {
        const view = variationView(variation);
        this.apply({
            nextCritical: true,
            prevMove: undefined,
            nextMove: view.currentPly >= view.sans.length - 1,
            fastRewind: true,
            fastForward: true,
            resumeGame: false,
            copyFen: !this.boardExists,
            flipBoard: !this.boardExists
        });
    }

    setPostCorrectGuess(variation) {
        const view = variationView(variation);
        this.apply({
            nextCritical: true,
            prevMove: undefined,
            nextMove: variationNextArrayIndex(view.currentPly, view.startIndex) >= view.sans.length,
            fastRewind: undefined,
            fastForward: undefined,
            resumeGame: false,
            copyFen: undefined,
            flipBoard: undefined
        });
    }

    setMain(position = {}, response = {}) {
        const moveIndex = position.moveIndex || 0;
        const totalPositions = position.totalPositions || 1;
        this.apply({
            nextCritical: this.nextCriticalDisabled(response),
            prevMove: undefined,
            nextMove: moveIndex >= totalPositions - 1,
            fastRewind: moveIndex === 0,
            fastForward: moveIndex >= totalPositions - 1,
            resumeGame: true,
            copyFen: !this.boardExists,
            flipBoard: !this.boardExists
        });
    }

    apply(states) {
        for (const name of ALL_BUTTONS) {
            const disabled = states[name];
            if (disabled === undefined) continue;
            const element = this.buttons[name];
            if (element) element.disabled = disabled;
        }
    }

    nextCriticalDisabled(response = {}) {
        if (response.url === '/api/load_game') {
            return !(response.hasInitialCriticalForWhite && this.learningSide === 'white');
        }
        return response.url === '/game/next_critical_moment' &&
            (response.serverMessage || '').startsWith('No further critical moments found');
    }
}

function allDisabled() {
    return ALL_BUTTONS.reduce((states, name) => {
        states[name] = true;
        return states;
    }, {});
}

function variationView(variation = {}) {
    return {
        currentPly: variation.currentPly ?? 0,
        sans: variation.sans ?? [],
        startIndex: variation.startIndex ?? 0
    };
}
