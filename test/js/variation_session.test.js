import { describe, it, expect } from 'vitest';
import { VariationSession } from '../../public/scripts/variation_session.js';

class FakeChess {
    constructor(fen) {
        this.positions = [fen];
        this.moves = [];
    }

    move(san) {
        this.moves.push(san);
        this.positions.push(`fen-after-${this.moves.join('-')}`);
        return {};
    }

    undo() {
        this.moves.pop();
        this.positions.pop();
    }

    fen() {
        return this.positions[this.positions.length - 1];
    }
}

const lastMoveData = {
    number: 17,
    variation_sans: ['e5', 'Rc5'],
    move_index_of_blunder: 34
};

describe('VariationSession', () => {
    it('owns variation playback state after a correct guess', () => {
        const session = new VariationSession(FakeChess);
        const plan = session.start({
            moveAttempt: { userMoveUci: 'e7e5', goodMoveUci: 'e7e5', userMoveSan: 'e5' },
            lastMoveData,
            validationData: {},
            fenAtPrompt: 'fen-before-blunder',
            learningSide: 'black'
        });

        expect(session.active).toBe(true);
        expect(session.fenAtPrompt).toBe('fen-before-blunder');
        expect(session.currentPly).toBe(1);
        expect(session.currentFen).toBe('fen-after-e5');
        expect(session.positionBeforeBlunder()).toBe(33);
        expect(session.nextSan()).toBe('Rc5');
        expect(plan.savePayload).toBeNull();
    });
});
