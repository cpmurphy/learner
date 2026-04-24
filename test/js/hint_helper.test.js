import { describe, it, expect } from 'vitest';
import { bestMoveHint } from '../../public/scripts/hint_helper.js';

describe('bestMoveHint', () => {
    describe('pawns', () => {
        it('names the file when multiple pawns of the side remain', () => {
            const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
            expect(bestMoveHint(fen, 'e4')).toBe('Try moving your e pawn');
        });

        it('handles black pawns with the matching file', () => {
            const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
            expect(bestMoveHint(fen, 'e5')).toBe('Try moving your e pawn');
        });

        it('handles a capturing pawn move (file of the from-square)', () => {
            const fen = 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2';
            expect(bestMoveHint(fen, 'exd5')).toBe('Try moving your e pawn');
        });

        it('omits the file when only one pawn of the side remains', () => {
            const fen = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';
            expect(bestMoveHint(fen, 'e4')).toBe('Try moving your pawn');
        });
    });

    describe('non-pawn pieces', () => {
        it('describes a knight move with its from-square', () => {
            const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
            expect(bestMoveHint(fen, 'Nf3')).toBe('Try moving your knight on g1');
        });

        it('describes a bishop move with its from-square', () => {
            const fen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
            expect(bestMoveHint(fen, 'Bc4')).toBe('Try moving your bishop on f1');
        });

        it('describes a rook move with its from-square', () => {
            const fen = '4k3/8/8/8/8/8/8/R3K3 w Q - 0 1';
            expect(bestMoveHint(fen, 'Ra5')).toBe('Try moving your rook on a1');
        });

        it('describes a queen move with its from-square', () => {
            const fen = '4k3/8/8/8/8/8/8/3QK3 w - - 0 1';
            expect(bestMoveHint(fen, 'Qd5')).toBe('Try moving your queen on d1');
        });

        it('describes a king move with its from-square', () => {
            const fen = '4k3/8/8/8/8/8/8/4K3 w - - 0 1';
            expect(bestMoveHint(fen, 'Ke2')).toBe('Try moving your king on e1');
        });

        it('describes a black knight move with its from-square', () => {
            const fen = 'r1bqkbnr/pppppppp/2n5/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2';
            expect(bestMoveHint(fen, 'e5')).toBe('Try moving your e pawn');
        });

        it('uses the from-square even for black pieces', () => {
            const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
            expect(bestMoveHint(fen, 'Nf6')).toBe('Try moving your knight on g8');
        });
    });

    describe('error handling', () => {
        it('returns null when SAN is missing', () => {
            const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
            expect(bestMoveHint(fen, null)).toBeNull();
        });

        it('returns null when FEN is missing', () => {
            expect(bestMoveHint(null, 'e4')).toBeNull();
        });

        it('returns null when the move is illegal for the position', () => {
            const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
            expect(bestMoveHint(fen, 'e9')).toBeNull();
        });
    });
});
