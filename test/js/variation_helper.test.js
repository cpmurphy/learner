import { describe, it, expect } from 'vitest';
import {
    variationMoveNumber,
    variationTurn,
    variationDisplayArrayIndex,
    variationNextArrayIndex
} from '../../public/scripts/variation_helper.js';

describe('variationMoveNumber', () => {
    describe('variation starting with Black (e.g. replacing 17...Rfe8 with 17...e5)', () => {
        const startMoveNumber = 17;
        const startTurn = 'black';

        it('ply 1 (Black replaces blunder) should be move 17', () => {
            expect(variationMoveNumber(startMoveNumber, startTurn, 1)).toBe(17);
        });

        it('ply 2 (White responds) should be move 18', () => {
            expect(variationMoveNumber(startMoveNumber, startTurn, 2)).toBe(18);
        });

        it('ply 3 (Black continues) should be move 18', () => {
            expect(variationMoveNumber(startMoveNumber, startTurn, 3)).toBe(18);
        });

        it('ply 4 (White continues) should be move 19', () => {
            expect(variationMoveNumber(startMoveNumber, startTurn, 4)).toBe(19);
        });
    });

    describe('variation starting with White (e.g. replacing 10. Nf3 with 10. d4)', () => {
        const startMoveNumber = 10;
        const startTurn = 'white';

        it('ply 1 (White replaces blunder) should be move 10', () => {
            expect(variationMoveNumber(startMoveNumber, startTurn, 1)).toBe(10);
        });

        it('ply 2 (Black responds) should be move 10', () => {
            expect(variationMoveNumber(startMoveNumber, startTurn, 2)).toBe(10);
        });

        it('ply 3 (White continues) should be move 11', () => {
            expect(variationMoveNumber(startMoveNumber, startTurn, 3)).toBe(11);
        });

        it('ply 4 (Black continues) should be move 11', () => {
            expect(variationMoveNumber(startMoveNumber, startTurn, 4)).toBe(11);
        });
    });
});

describe('variationTurn', () => {
    describe('variation starting with Black', () => {
        it('ply 1 should be black', () => {
            expect(variationTurn('black', 1)).toBe('black');
        });

        it('ply 2 should be white', () => {
            expect(variationTurn('black', 2)).toBe('white');
        });

        it('ply 3 should be black', () => {
            expect(variationTurn('black', 3)).toBe('black');
        });

        it('ply 4 should be white', () => {
            expect(variationTurn('black', 4)).toBe('white');
        });
    });

    describe('variation starting with White', () => {
        it('ply 1 should be white', () => {
            expect(variationTurn('white', 1)).toBe('white');
        });

        it('ply 2 should be black', () => {
            expect(variationTurn('white', 2)).toBe('black');
        });

        it('ply 3 should be white', () => {
            expect(variationTurn('white', 3)).toBe('white');
        });
    });
});

describe('variationDisplayArrayIndex', () => {
    describe('user move is in the array (variationSANsStartIndex = 0)', () => {
        // currentVariationSANs = [userMove, opponentMove, ...]
        const startIndex = 0;

        it('at ply 1 (after user move) should return index 0 (user move)', () => {
            expect(variationDisplayArrayIndex(1, startIndex)).toBe(0);
        });

        it('at ply 2 (after opponent move) should return index 1 (opponent move)', () => {
            expect(variationDisplayArrayIndex(2, startIndex)).toBe(1);
        });

        it('at ply 3 should return index 2', () => {
            expect(variationDisplayArrayIndex(3, startIndex)).toBe(2);
        });
    });

    describe('user move was sliced off (variationSANsStartIndex = 1)', () => {
        // currentVariationSANs = [opponentMove, ...]
        // user move stored separately in userMoveSanInVariation
        const startIndex = 1;

        it('at ply 1 should return -1 (user move is not in array)', () => {
            expect(variationDisplayArrayIndex(1, startIndex)).toBe(-1);
        });

        it('at ply 2 (after opponent move) should return index 0', () => {
            expect(variationDisplayArrayIndex(2, startIndex)).toBe(0);
        });

        it('at ply 3 should return index 1', () => {
            expect(variationDisplayArrayIndex(3, startIndex)).toBe(1);
        });
    });
});

describe('variationNextArrayIndex', () => {
    describe('user move is in the array (variationSANsStartIndex = 0)', () => {
        const startIndex = 0;

        it('at ply 1 should return index 1 (next move after user move)', () => {
            expect(variationNextArrayIndex(1, startIndex)).toBe(1);
        });

        it('at ply 2 should return index 2', () => {
            expect(variationNextArrayIndex(2, startIndex)).toBe(2);
        });
    });

    describe('user move was sliced off (variationSANsStartIndex = 1)', () => {
        const startIndex = 1;

        it('at ply 1 should return index 0 (opponent response)', () => {
            expect(variationNextArrayIndex(1, startIndex)).toBe(0);
        });

        it('at ply 2 should return index 1', () => {
            expect(variationNextArrayIndex(2, startIndex)).toBe(1);
        });
    });
});

describe('Black variation scenario: 17...e5 replacing 17...Rfe8', () => {
    // Simulates the exact bug scenario from the issue
    const startMoveNumber = 17;
    const startTurn = 'black';
    // User played the expected move, so variation_sans includes it
    const variationSANs = ['e5', 'Rc5', 'Qf4', 'Nd2'];
    const startIndex = 0;

    it('after user guesses e5 (ply 1): should display "17... e5"', () => {
        const ply = 1;
        expect(variationMoveNumber(startMoveNumber, startTurn, ply)).toBe(17);
        expect(variationTurn(startTurn, ply)).toBe('black');
    });

    it('after forward to Rc5 (ply 2): should display "18. Rc5"', () => {
        const ply = 2;
        expect(variationMoveNumber(startMoveNumber, startTurn, ply)).toBe(18);
        expect(variationTurn(startTurn, ply)).toBe('white');
    });

    it('after pressing prev from ply 2 back to ply 1: display index should point to e5', () => {
        const ply = 1; // after undo
        const displayIdx = variationDisplayArrayIndex(ply, startIndex);
        expect(displayIdx).toBe(0);
        expect(variationSANs[displayIdx]).toBe('e5');
    });

    it('next move index at ply 1 should point to Rc5', () => {
        const ply = 1;
        const nextIdx = variationNextArrayIndex(ply, startIndex);
        expect(nextIdx).toBe(1);
        expect(variationSANs[nextIdx]).toBe('Rc5');
    });

    it('after Qf4 (ply 3): should display "18... Qf4"', () => {
        const ply = 3;
        expect(variationMoveNumber(startMoveNumber, startTurn, ply)).toBe(18);
        expect(variationTurn(startTurn, ply)).toBe('black');
    });

    it('after Nd2 (ply 4): should display "19. Nd2"', () => {
        const ply = 4;
        expect(variationMoveNumber(startMoveNumber, startTurn, ply)).toBe(19);
        expect(variationTurn(startTurn, ply)).toBe('white');
    });
});
