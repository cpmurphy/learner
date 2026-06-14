import { describe, it, expect } from 'vitest';
import { CriticalChallenge, getGameIdFromURL } from '../../public/scripts/game_utils_helper.js';

describe('getGameIdFromURL', () => {
    it('extracts id from query string', () => {
        expect(getGameIdFromURL('?id=my-game.pgn')).toBe('my-game.pgn');
    });

    it('returns null when id is missing', () => {
        expect(getGameIdFromURL('')).toBeNull();
        expect(getGameIdFromURL('?other=1')).toBeNull();
    });
});

describe('CriticalChallenge', () => {
    const criticalMove = {
        is_critical: true,
        turn: 'white',
        good_move_san: 'Nf3',
        fen_before_move: 'fen-before'
    };

    it('starts when all critical-moment conditions are met', () => {
        const challenge = new CriticalChallenge();
        expect(challenge.prepare(criticalMove, 'white')).toBe(true);
        expect(challenge.active).toBe(true);
        expect(challenge.fenAtPrompt).toBe('fen-before');
        expect(challenge.goodMoveSan).toBe('Nf3');
    });

    it('does not start when learning side does not match', () => {
        const challenge = new CriticalChallenge();
        expect(challenge.prepare(criticalMove, 'black')).toBe(false);
        expect(challenge.active).toBe(false);
    });

    it('stops when a non-critical response is prepared', () => {
        const challenge = new CriticalChallenge();
        challenge.prepare(criticalMove, 'white');
        challenge.prepare({ ...criticalMove, is_critical: false }, 'white');
        expect(challenge.active).toBe(false);
        expect(challenge.fenAtPrompt).toBeNull();
    });

    it('selects the prompt FEN while active and server FEN otherwise', () => {
        const challenge = new CriticalChallenge();
        challenge.prepare(criticalMove, 'white');
        expect(challenge.displayFen('fen-after')).toBe('fen-before');
        expect(challenge.fenToCopy()).toBe('fen-before');

        challenge.stop();
        expect(challenge.displayFen('fen-after')).toBe('fen-after');
        expect(challenge.fenToCopy()).toBeNull();
    });
});
