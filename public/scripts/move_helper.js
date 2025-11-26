import { Chess } from './3rdparty/chess.js/chess.js';

/**
 * MoveHelper class provides utilities for working with chess moves.
 * It can generate SAN from move parameters and convert SAN to square coordinates.
 */
export class MoveHelper {
    /**
     * @param {string} fen - The FEN string representing the board state before the move.
     * @param {string} fromSquare - The source square of the move (e.g., "e2").
     * @param {string} toSquare - The target square of the move (e.g., "e4").
     * @param {string|null} [promotionPiece=null] - The piece to promote to (e.g., "q"), if any.
     */
    constructor(fen, fromSquare, toSquare, promotionPiece = null) {
        this.fen = fen;
        this.fromSquare = fromSquare;
        this.toSquare = toSquare;
        this.promotionPiece = promotionPiece; // e.g., "q", "n", "b", "r"
    }

    /**
     * Generates the SAN for the move.
     * @returns {string|null} The SAN string if the move is valid, otherwise null.
     */
    getSan() {
        if (!this.fen || !this.fromSquare || !this.toSquare) {
            console.error("MoveHelper: FEN, fromSquare, or toSquare is missing.");
            return null;
        }
        try {
            const chessInstance = new Chess(this.fen);
            const moveDetails = {
                from: this.fromSquare,
                to: this.toSquare
            };
            if (this.promotionPiece) {
                // chess.js expects promotion piece to be lowercase
                moveDetails.promotion = this.promotionPiece.toLowerCase();
            }

            const moveResult = chessInstance.move(moveDetails);

            if (moveResult) {
                return moveResult.san;
            } else {
                // This can happen if the move is illegal for the given FEN (e.g., wrong turn, invalid move)
                console.warn("MoveHelper: chess.js considered the move illegal or invalid for the FEN.",
                             { fen: this.fen, from: this.fromSquare, to: this.toSquare, promotion: this.promotionPiece });
                return null;
            }
        } catch (e) {
            // Catch errors from chess.js instantiation (e.g., invalid FEN) or other issues
            console.error("MoveHelper: Error during SAN generation:", e,
                          { fen: this.fen, from: this.fromSquare, to: this.toSquare, promotion: this.promotionPiece });
            return null;
        }
    }

    /**
     * Converts SAN to a list of move objects and, for en passant, a square to remove.
     * @param {string} san
     * @param {string} fen
     * @returns {{ moves: Array<{from: string, to: string}>, remove?: string } | null}
     */
    static sanToSquares(san, fen) {
        if (!fen || typeof fen !== 'string') {
            console.error("MoveHelper.sanToSquares: Invalid FEN parameter:", fen);
            return null;
        }
        // Basic FEN validation - should have 6 space-delimited fields
        const fenParts = fen.trim().split(/\s+/);
        if (fenParts.length !== 6) {
            console.error("MoveHelper.sanToSquares: FEN must have 6 space-delimited fields, got:", fenParts.length, "parts:", fenParts);
            return null;
        }
        try {
            const chess = new Chess(fen);
            // Use the public API to get the move object
            const move = chess.move(san, { sloppy: true });
            if (move) {
                const fromSquare = move.from;
                const toSquare = move.to;
                const moves = [{ from: fromSquare, to: toSquare }];
                // Use descriptor functions for castling
                const isWhite = move.color === 'w';
                if (typeof move.isKingsideCastle === 'function' && move.isKingsideCastle()) {
                    moves.push({
                        from: isWhite ? 'h1' : 'h8',
                        to: isWhite ? 'f1' : 'f8'
                    });
                } else if (typeof move.isQueensideCastle === 'function' && move.isQueensideCastle()) {
                    moves.push({
                        from: isWhite ? 'a1' : 'a8',
                        to: isWhite ? 'd1' : 'd8'
                    });
                }
                // Handle en passant
                if (typeof move.isEnPassant === 'function' && move.isEnPassant()) {
                    // The captured pawn is on the same rank as the from-square, file of the to-square
                    // Example: e5xd6 (white pawn on e5 captures black pawn on d5 via en passant, moves to d6, remove d5)
                    const fromRank = fromSquare[1];
                    const toFile = toSquare[0];
                    const removeRank = isWhite ? (parseInt(toSquare[1]) - 1).toString() : (parseInt(toSquare[1]) + 1).toString();
                    const removeSquare = toFile + removeRank;
                    return { moves, remove: removeSquare };
                }
                return { moves };
            }
            return null;
        } catch (e) {
            console.error("Error converting SAN to squares:", e);
            return null;
        }
    }
}
