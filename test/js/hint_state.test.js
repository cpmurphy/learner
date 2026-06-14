import { describe, it, expect } from 'vitest';
import { HintState } from '../../public/scripts/hint_state.js';

describe('HintState', () => {
    it('enables the hint after three wrong guesses', () => {
        const button = { disabled: true };
        const hints = new HintState({ button, arrowType: 'default' });
        hints.recordWrongGuess(null, null);
        hints.recordWrongGuess(null, null);
        expect(button.disabled).toBe(true);

        hints.recordWrongGuess(null, null);
        expect(button.disabled).toBe(false);
    });

    it('shows an arrow after six wrong guesses once the hint was shown', () => {
        const calls = [];
        const board = { addArrow: (...args) => calls.push(args) };
        const hints = new HintState({ arrowType: 'default' });
        hints.hintShown = true;

        for (let i = 0; i < 6; i++) {
            hints.recordWrongGuess(board, { from: 'e2', to: 'e4' });
        }

        expect(calls).toEqual([['default', 'e2', 'e4']]);
    });

    it('resets button, bubble, counters, and board arrows', () => {
        const button = { disabled: false };
        const bubble = { style: { display: 'block' }, textContent: 'hint' };
        const board = { removeArrowsCalled: false, removeArrows() { this.removeArrowsCalled = true; } };
        const hints = new HintState({ button, bubble });
        hints.wrongGuessCount = 5;
        hints.hintShown = true;
        hints.arrowShown = true;

        hints.reset(board);

        expect(button.disabled).toBe(true);
        expect(bubble.style.display).toBe('none');
        expect(bubble.textContent).toBe('');
        expect(hints.wrongGuessCount).toBe(0);
        expect(hints.hintShown).toBe(false);
        expect(hints.arrowShown).toBe(false);
        expect(board.removeArrowsCalled).toBe(true);
    });
});
