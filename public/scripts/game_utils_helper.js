/**
 * Focused game-level state helpers used by the browser UI.
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
 * Owns the current critical-moment prompt state.
 */
export class CriticalChallenge {
    constructor() {
        this.stop();
    }

    get active() {
        return this.inProgress;
    }

    get fenAtPrompt() {
        return this.fen;
    }

    get goodMoveSan() {
        return this.goodSan;
    }

    shouldStart(lastMoveData, learningSide) {
        return !!(lastMoveData &&
            lastMoveData.is_critical &&
            lastMoveData.turn === learningSide &&
            lastMoveData.good_move_san &&
            lastMoveData.fen_before_move);
    }

    start(lastMoveData) {
        this.inProgress = true;
        this.fen = lastMoveData.fen_before_move;
        this.goodSan = lastMoveData.good_move_san;
    }

    stop() {
        this.inProgress = false;
        this.fen = null;
        this.goodSan = null;
    }

    prepare(lastMoveData, learningSide) {
        if (!this.shouldStart(lastMoveData, learningSide)) {
            this.stop();
            return false;
        }
        this.start(lastMoveData);
        return true;
    }

    displayFen(serverFen) {
        return this.active ? this.fen : serverFen;
    }

    fenToCopy() {
        return this.active ? this.fen : null;
    }
}
