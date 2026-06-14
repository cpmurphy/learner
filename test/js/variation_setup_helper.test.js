import { describe, it, expect } from 'vitest';
import { buildVariationState } from '../../public/scripts/variation_setup_helper.js';

const lastMoveData = {
    number: 17,
    variation_sans: ['e5', 'Rc5', 'Qf4', 'Nd2'],
    move_index_of_blunder: 34
};

describe('buildVariationState', () => {
    it('uses PGN variation when user played the expected move', () => {
        const result = buildVariationState(
            { userMoveUci: 'e7e5', goodMoveUci: 'e7e5', userMoveSan: 'e5' },
            { lastMoveData, validationData: {} }
        );

        expect(result.sans).toEqual(['e5', 'Rc5', 'Qf4', 'Nd2']);
        expect(result.startIndex).toBe(0);
        expect(result.savePayload).toBeNull();
    });

    it('slices validation variation and prepares save payload for alternate good move', () => {
        const result = buildVariationState(
            { userMoveUci: 'f7f5', goodMoveUci: 'e7e5', userMoveSan: 'f5' },
            { lastMoveData, validationData: { variation_sans: ['f5', 'Nf3', 'Nc6'] } }
        );

        expect(result.sans).toEqual(['Nf3', 'Nc6']);
        expect(result.startIndex).toBe(1);
        expect(result.savePayload).toEqual({
            move_index: 33,
            variation_sans: ['f5', 'Nf3', 'Nc6'],
            user_move_san: 'f5'
        });
    });

    it('falls back to user move only when no variation is available', () => {
        const result = buildVariationState(
            { userMoveUci: 'd7d5', goodMoveUci: 'e7e5', userMoveSan: 'd5' },
            { lastMoveData: { ...lastMoveData, variation_sans: [] }, validationData: {} }
        );

        expect(result.sans).toEqual(['d5']);
        expect(result.startIndex).toBe(0);
        expect(result.savePayload).toBeNull();
    });

    it('uses validation variation when expected move UCI matches but PGN variation is empty', () => {
        const result = buildVariationState(
            { userMoveUci: 'e7e5', goodMoveUci: 'e7e5', userMoveSan: 'e5' },
            { lastMoveData: { ...lastMoveData, variation_sans: [] }, validationData: { variation_sans: ['e5', 'Nc3'] } }
        );

        // UCI matches but variation_sans length is 0, so falls through to validation
        expect(result.sans).toEqual(['Nc3']);
        expect(result.startIndex).toBe(1);
        expect(result.savePayload).toEqual({
            move_index: 33,
            variation_sans: ['e5', 'Nc3'],
            user_move_san: 'e5'
        });
    });
});
