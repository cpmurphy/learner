import { Chess } from 'chess.js';

/**
 * SanGenerator class takes a FEN string and move parameters to generate
 * the Standard Algebraic Notation (SAN) for that move.
 */
export class SanGenerator {
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
            console.error("SanGenerator: FEN, fromSquare, or toSquare is missing.");
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
                console.warn("SanGenerator: chess.js considered the move illegal or invalid for the FEN.", 
                             { fen: this.fen, from: this.fromSquare, to: this.toSquare, promotion: this.promotionPiece });
                return null;
            }
        } catch (e) {
            // Catch errors from chess.js instantiation (e.g., invalid FEN) or other issues
            console.error("SanGenerator: Error during SAN generation:", e, 
                          { fen: this.fen, from: this.fromSquare, to: this.toSquare, promotion: this.promotionPiece });
            return null;
        }
    }
}
