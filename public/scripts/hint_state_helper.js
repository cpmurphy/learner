import { bestMoveHint } from './hint_helper.js';

/**
 * Owns hint UI state for a critical-moment challenge.
 */
export class HintState {
    constructor(elements = {}) {
        this.button = elements.button || null;
        this.bubble = elements.bubble || null;
        this.arrowType = elements.arrowType;
        this.reset();
    }

    reset(board = null) {
        this.wrongGuessCount = 0;
        this.hintShown = false;
        this.arrowShown = false;
        if (this.button) this.button.disabled = true;
        if (this.bubble) {
            this.bubble.style.display = 'none';
            this.bubble.textContent = '';
        }
        if (board?.removeArrows) board.removeArrows();
    }

    recordWrongGuess(board, goodMove) {
        this.wrongGuessCount++;
        if (this.canEnableHint() && this.button) {
            this.button.disabled = false;
        }
        if (this.canShowArrow() && board?.addArrow && goodMove) {
            board.addArrow(this.arrowType, goodMove.from, goodMove.to);
            this.arrowShown = true;
        }
    }

    show(fen, goodMoveSan) {
        const hintText = bestMoveHint(fen, goodMoveSan);
        if (!hintText) return null;

        if (this.bubble) {
            this.bubble.textContent = hintText;
            this.bubble.style.display = 'block';
            this.positionBubbleArrow();
        }
        this.hintShown = true;
        if (this.button) this.button.disabled = true;
        return hintText;
    }

    canEnableHint() {
        return !this.hintShown && this.wrongGuessCount >= 3;
    }

    canShowArrow() {
        return this.hintShown && this.wrongGuessCount >= 6 && !this.arrowShown;
    }

    positionBubbleArrow() {
        if (!this.button || !this.bubble) return;
        const buttonRect = this.button.getBoundingClientRect();
        const bubbleRect = this.bubble.getBoundingClientRect();
        const buttonCenterX = buttonRect.left + buttonRect.width / 2;
        const arrowX = buttonCenterX - bubbleRect.left;
        const clampedArrowX = Math.max(12, Math.min(bubbleRect.width - 12, arrowX));
        this.bubble.style.setProperty('--arrow-x', `${clampedArrowX}px`);
    }
}
