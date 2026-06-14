import { Chess } from './3rdparty/chess.js/chess.js';
import { variationDisplayArrayIndex, variationNextArrayIndex } from './variation_helper.js';
import { buildVariationState } from './variation_setup_helper.js';

/**
 * Owns variation playback state after a correct critical-moment guess.
 */
export class VariationSession {
    constructor(ChessCtor = Chess) {
        this.ChessCtor = ChessCtor;
        this.reset();
    }

    get active() {
        return this.inProgress;
    }

    get currentPly() {
        return this.ply;
    }

    get sans() {
        return this.variationSans;
    }

    get startIndex() {
        return this.startIndexValue;
    }

    get currentFen() {
        return this.fen;
    }

    start(context) {
        const plan = buildVariationState(
            context.moveAttempt,
            { lastMoveData: context.lastMoveData, validationData: context.validationData }
        );

        this.inProgress = true;
        this.mainLineMoveIndex = context.lastMoveData.move_index_of_blunder;
        this.startMoveNumber = context.lastMoveData.number;
        this.startTurn = context.learningSide;
        this.variationSans = plan.sans;
        this.startIndexValue = plan.startIndex;
        this.savePayload = plan.savePayload;
        this.userMoveSan = context.moveAttempt.userMoveSan;
        this.fenAtPrompt = context.fenAtPrompt;
        this.chess = new this.ChessCtor(context.fenAtPrompt);
        this.chess.move(this.userMoveSan, { sloppy: true });
        this.fen = this.chess.fen();
        this.ply = 1;
        return plan;
    }

    reset() {
        this.inProgress = false;
        this.mainLineMoveIndex = 0;
        this.startMoveNumber = 0;
        this.startTurn = null;
        this.variationSans = [];
        this.startIndexValue = 0;
        this.savePayload = null;
        this.userMoveSan = null;
        this.fenAtPrompt = null;
        this.chess = null;
        this.fen = null;
        this.ply = 0;
    }

    positionBeforeBlunder() {
        return this.mainLineMoveIndex - 1;
    }

    nextArrayIndex() {
        return variationNextArrayIndex(this.ply, this.startIndexValue);
    }

    displayArrayIndex() {
        return variationDisplayArrayIndex(this.ply, this.startIndexValue);
    }

    nextSan() {
        return this.variationSans[this.nextArrayIndex()] || null;
    }

    canAdvance() {
        return this.nextArrayIndex() < this.variationSans.length;
    }

    applySan(san) {
        this.chess.move(san, { sloppy: true });
        this.fen = this.chess.fen();
        this.ply++;
    }

    undo() {
        if (!this.chess || this.ply <= 1) return false;
        this.chess.undo();
        this.ply--;
        this.fen = this.chess.fen();
        return true;
    }

    displayedSan() {
        const arrayIndex = this.displayArrayIndex();
        if (arrayIndex >= 0 && arrayIndex < this.variationSans.length) {
            return this.variationSans[arrayIndex];
        }
        return this.ply === 1 ? this.userMoveSan : null;
    }
}
