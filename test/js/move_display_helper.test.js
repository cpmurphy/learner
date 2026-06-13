import { describe, it, expect } from 'vitest';
import {
    formatMainLineMoveText,
    formatVariationMoveText,
    formatCriticalPromptText,
    formatMoveInfoText
} from '../../public/scripts/move_display_helper.js';

describe('formatMainLineMoveText', () => {
    it('formats a white move with move number prefix', () => {
        const text = formatMainLineMoveText({ number: 10, turn: 'white', san: 'Nf3' }, 'white');
        expect(text).toBe('10. Nf3');
    });

    it('formats a black move with ellipsis prefix', () => {
        const text = formatMainLineMoveText({ number: 17, turn: 'black', san: 'Rfe8' }, 'white');
        expect(text).toBe('17... Rfe8');
    });

    it('appends single ? for centipawn loss up to 100', () => {
        const text = formatMainLineMoveText(
            { number: 5, turn: 'white', san: 'h3', centipawn_loss: 80 },
            'white'
        );
        expect(text).toBe('5. h3 ?');
    });

    it('appends ?? for centipawn loss over 100', () => {
        const text = formatMainLineMoveText(
            { number: 5, turn: 'white', san: 'h3', centipawn_loss: 150 },
            'white'
        );
        expect(text).toBe('5. h3 ??');
    });

    it('includes user comment for learning side moves', () => {
        const text = formatMainLineMoveText(
            { number: 3, turn: 'white', san: 'e4', comment: 'Best by test' },
            'white'
        );
        expect(text).toBe('3. e4 {Best by test}');
    });

    it('excludes cp_loss internal comments', () => {
        const text = formatMainLineMoveText(
            { number: 3, turn: 'white', san: 'e4', comment: 'cp_loss: 200' },
            'white'
        );
        expect(text).toBe('3. e4');
    });

    it('does not include comments for opponent moves', () => {
        const text = formatMainLineMoveText(
            { number: 3, turn: 'black', san: 'e5', comment: 'Solid' },
            'white'
        );
        expect(text).toBe('3... e5');
    });
});

describe('formatVariationMoveText', () => {
    it('formats black variation start at move 17', () => {
        const text = formatVariationMoveText('e5', 17, 'black', 1);
        expect(text).toBe('Variation: 17... e5');
    });

    it('formats white response at move 18 in black-started variation', () => {
        const text = formatVariationMoveText('Rc5', 17, 'black', 2);
        expect(text).toBe('Variation: 18. Rc5');
    });
});

describe('formatCriticalPromptText', () => {
    it('prompts user to find a better move', () => {
        const text = formatCriticalPromptText(
            { number: 17, turn: 'black', san: 'Rfe8' },
            'white'
        );
        expect(text).toBe('17...Rfe8 played. Try a better move for white.');
    });
});

describe('formatMoveInfoText', () => {
    it('returns game start text when lastMoveData is null', () => {
        expect(formatMoveInfoText(null, 'white')).toBe('Game start.');
    });

    it('delegates to main line formatter', () => {
        const text = formatMoveInfoText(
            { number: 1, turn: 'white', san: 'e4' },
            'white'
        );
        expect(text).toBe('1. e4');
    });

    it('delegates to variation formatter when isVariationMove is true', () => {
        const text = formatMoveInfoText(
            { san: 'e5' },
            'white',
            { isVariationMove: true, variationPly: 1, variationStartMoveNumber: 17, variationStartTurn: 'black' }
        );
        expect(text).toBe('Variation: 17... e5');
    });
});
