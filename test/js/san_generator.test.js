import { describe, it, expect } from 'vitest';
import { SanGenerator } from '../../public/scripts/san_generator.js';

describe('SanGenerator', () => {
    it('should generate SAN for a simple pawn move (e4)', () => {
        const startingFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
        const gen = new SanGenerator(startingFen, 'e2', 'e4');
        expect(gen.getSan()).toBe('e4');
    });

    it('should generate SAN for a simple knight move (Nf3)', () => {
        const startingFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
        const gen = new SanGenerator(startingFen, 'g1', 'f3');
        expect(gen.getSan()).toBe('Nf3');
    });

    it('should generate SAN for a pawn promotion to Queen (b8=Q)', () => {
        const promotionFen = "r1bqk1nr/pPpp1ppp/8/4p3/8/8/PPP1PPPP/RNBQKBNR w KQkq - 0 1";
        const gen = new SanGenerator(promotionFen, 'b7', 'b8', 'q');
        expect(gen.getSan()).toBe('b8=Q');
    });
    
    it('should generate SAN for a pawn promotion to Knight (b8=N)', () => {
        const promotionFen = "r1bqk1nr/pPpp1ppp/8/4p3/8/8/PPP1PPPP/RNBQKBNR w KQkq - 0 1";
        const gen = new SanGenerator(promotionFen, 'b7', 'b8', 'n');
        expect(gen.getSan()).toBe('b8=N');
    });

    it('should generate SAN for white kingside castling (O-O)', () => {
        const castlingFenWhite = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1";
        const gen = new SanGenerator(castlingFenWhite, 'e1', 'g1');
        expect(gen.getSan()).toBe('O-O');
    });

    it('should generate SAN for white queenside castling (O-O-O)', () => {
        const castlingFenWhite = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1";
        const gen = new SanGenerator(castlingFenWhite, 'e1', 'c1');
        expect(gen.getSan()).toBe('O-O-O');
    });
    
    it('should generate SAN for black kingside castling (O-O)', () => {
        const blackTurnCastlingFen = "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1";
        const gen = new SanGenerator(blackTurnCastlingFen, 'e8', 'g8');
        expect(gen.getSan()).toBe('O-O');
    });

    it('should generate SAN for a pawn capture (exd5)', () => {
        const captureFen = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2"; // After 1. e4 d5
        const gen = new SanGenerator(captureFen, 'e4', 'd5');
        expect(gen.getSan()).toBe('exd5');
    });

    it('should generate SAN with file disambiguation for knight (Nbd2)', () => {
        const disambiguationFen = "r1bqkbnr/pppppppp/8/8/8/5N2/PPP1PPPP/1N1QKB1R w Kkq - 0 1";
        const gen = new SanGenerator(disambiguationFen, 'b1', 'd2');
        expect(gen.getSan()).toBe('Nbd2');
    });

    it('should generate SAN with file disambiguation for knight (Nfd2)', () => {
        const disambiguationFen = "r1bqkbnr/pppppppp/8/8/8/5N2/PPP1PPPP/1N1QKB1R w Kkq - 0 1";
        const gen = new SanGenerator(disambiguationFen, 'f3', 'd2');
        expect(gen.getSan()).toBe('Nfd2');
    });

    it('should return null for an illegal move (e.g. Rook trying to move like a Knight)', () => {
        const startingFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
        const gen = new SanGenerator(startingFen, 'a1', 'c2'); // Invalid move for a rook
        expect(gen.getSan()).toBeNull();
    });
    
    it('should return null if the move is for the wrong turn', () => {
        const startingFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
        // startingFen is white's turn. Attempting a black move.
        const gen = new SanGenerator(startingFen, 'e7', 'e5');
        expect(gen.getSan()).toBeNull();
    });

    it('should return null for an invalid FEN string', () => {
        const gen = new SanGenerator("invalid fen", 'e2', 'e4');
        expect(gen.getSan()).toBeNull();
    });
    
    it('should return null if fromSquare is missing', () => {
        const startingFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
        const gen = new SanGenerator(startingFen, null, 'e4');
        expect(gen.getSan()).toBeNull();
    });
    it('should return null if the move is illegal (e.g. a move does not get king out of check)', () => {
        const kingInCheckFen = "r2qkb1r/p1p2ppp/4pn2/1Q2n3/4p3/2P5/PP1PNPPP/RNB1K2R b KQkq - 2 11";
        const gen = new SanGenerator(kingInCheckFen, 'f8', 'd6');
        expect(gen.getSan()).toBeNull();
    });
});
