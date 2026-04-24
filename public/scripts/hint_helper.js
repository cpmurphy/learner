import { Chess } from './3rdparty/chess.js/chess.js';

const PIECE_NAMES = {
    p: 'pawn',
    n: 'knight',
    b: 'bishop',
    r: 'rook',
    q: 'queen',
    k: 'king'
};

function countPawns(fen, color) {
    const placement = fen.split(/\s+/)[0] || '';
    const pawnChar = color === 'w' ? 'P' : 'p';
    let count = 0;
    for (const ch of placement) {
        if (ch === pawnChar) count++;
    }
    return count;
}

/**
 * Build a hint sentence for the best move at a critical moment.
 * @param {string} fen - FEN of the position before the best move is played.
 * @param {string} goodMoveSan - SAN of the best move.
 * @returns {string|null} Hint sentence, or null if the move cannot be parsed.
 */
export function bestMoveHint(fen, goodMoveSan) {
    if (!fen || !goodMoveSan) return null;

    let move;
    try {
        const chess = new Chess(fen);
        move = chess.move(goodMoveSan, { sloppy: true });
    } catch (e) {
        return null;
    }
    if (!move) return null;

    const pieceName = PIECE_NAMES[move.piece];
    if (!pieceName) return null;

    if (move.piece === 'p') {
        const pawnCount = countPawns(fen, move.color);
        if (pawnCount <= 1) {
            return 'Try moving your pawn';
        }
        const file = move.from[0];
        return `Try moving your ${file} pawn`;
    }

    return `Try moving your ${pieceName} on ${move.from}`;
}
