import { describe, it, expect } from 'vitest';
import {
    getGameIdFromURL,
    shouldStartCriticalChallenge,
    selectFenToCopy,
    shouldEnableHint,
    shouldShowArrow,
    fenToDisplay
} from '../../public/scripts/game_utils_helper.js';

describe('getGameIdFromURL', () => {
    it('extracts id from query string', () => {
        expect(getGameIdFromURL('?id=my-game.pgn')).toBe('my-game.pgn');
    });

    it('returns null when id is missing', () => {
        expect(getGameIdFromURL('')).toBeNull();
        expect(getGameIdFromURL('?other=1')).toBeNull();
    });
});

describe('shouldStartCriticalChallenge', () => {
    const criticalMove = {
        is_critical: true,
        turn: 'white',
        good_move_san: 'Nf3',
        fen_before_move: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1'
    };

    it('returns true when all conditions are met', () => {
        expect(shouldStartCriticalChallenge(criticalMove, 'white')).toBe(true);
    });

    it('returns false when learning side does not match', () => {
        expect(shouldStartCriticalChallenge(criticalMove, 'black')).toBe(false);
    });

    it('returns false when move is not critical', () => {
        expect(shouldStartCriticalChallenge({ ...criticalMove, is_critical: false }, 'white')).toBe(false);
    });

    it('returns false when lastMoveData is null', () => {
        expect(shouldStartCriticalChallenge(null, 'white')).toBe(false);
    });
});

describe('selectFenToCopy', () => {
    const criticalFen = 'fen-critical';
    const variationFen = 'fen-variation';
    const serverFen = 'fen-server';
    const boardFen = 'fen-board';

    it('prefers critical prompt FEN during challenge', () => {
        expect(selectFenToCopy({
            inCriticalMomentChallenge: true,
            fenAtCriticalPrompt: criticalFen,
            inVariationMode: true,
            currentFenInVariation: variationFen,
            lastKnownServerFEN: serverFen
        })).toBe(criticalFen);
    });

    it('uses variation FEN in variation mode', () => {
        expect(selectFenToCopy({
            inCriticalMomentChallenge: false,
            fenAtCriticalPrompt: null,
            inVariationMode: true,
            currentFenInVariation: variationFen,
            lastKnownServerFEN: serverFen
        })).toBe(variationFen);
    });

    it('uses server FEN on main line', () => {
        expect(selectFenToCopy({
            inCriticalMomentChallenge: false,
            fenAtCriticalPrompt: null,
            inVariationMode: false,
            currentFenInVariation: null,
            lastKnownServerFEN: serverFen
        })).toBe(serverFen);
    });

    it('falls back to board FEN', () => {
        expect(selectFenToCopy({
            inCriticalMomentChallenge: false,
            fenAtCriticalPrompt: null,
            inVariationMode: false,
            currentFenInVariation: null,
            lastKnownServerFEN: null,
            boardFen
        })).toBe(boardFen);
    });
});

describe('shouldEnableHint', () => {
    it('enables hint after 3 wrong guesses if not yet shown', () => {
        expect(shouldEnableHint(3, false)).toBe(true);
    });

    it('does not enable hint before 3 wrong guesses', () => {
        expect(shouldEnableHint(2, false)).toBe(false);
    });

    it('does not enable hint if already shown', () => {
        expect(shouldEnableHint(5, true)).toBe(false);
    });
});

describe('shouldShowArrow', () => {
    it('shows arrow after 6 wrong guesses when hint was shown', () => {
        expect(shouldShowArrow(6, true, false)).toBe(true);
    });

    it('does not show arrow if hint was not shown', () => {
        expect(shouldShowArrow(6, false, false)).toBe(false);
    });

    it('does not show arrow if already shown', () => {
        expect(shouldShowArrow(7, true, true)).toBe(false);
    });
});

describe('fenToDisplay', () => {
    it('shows pre-blunder FEN during critical challenge setup', () => {
        expect(fenToDisplay(true, 'fen-before', 'fen-after')).toBe('fen-before');
    });

    it('shows server FEN otherwise', () => {
        expect(fenToDisplay(false, 'fen-before', 'fen-after')).toBe('fen-after');
    });
});
