import { describe, it, expect } from 'vitest';
import { computeButtonStates } from '../../public/scripts/button_state_helper.js';

describe('computeButtonStates', () => {
    describe('error mode', () => {
        it('disables all navigation buttons', () => {
            const states = computeButtonStates({ mode: 'error' });
            expect(states).toEqual({
                nextCritical: true,
                prevMove: true,
                nextMove: true,
                fastRewind: true,
                fastForward: true,
                resumeGame: true,
                copyFen: true,
                flipBoard: true
            });
        });
    });

    describe('main mode', () => {
        it('enables next move when not at end', () => {
            const states = computeButtonStates({
                mode: 'main',
                boardExists: true,
                moveIndex: 5,
                totalPositions: 40
            });
            expect(states.nextMove).toBe(false);
            expect(states.fastRewind).toBe(false);
            expect(states.fastForward).toBe(false);
            expect(states.resumeGame).toBe(true);
        });

        it('disables next move and fast forward at last position', () => {
            const states = computeButtonStates({
                mode: 'main',
                boardExists: true,
                moveIndex: 39,
                totalPositions: 40
            });
            expect(states.nextMove).toBe(true);
            expect(states.fastForward).toBe(true);
        });

        it('disables fast rewind at start', () => {
            const states = computeButtonStates({
                mode: 'main',
                boardExists: true,
                moveIndex: 0,
                totalPositions: 40
            });
            expect(states.fastRewind).toBe(true);
        });

        it('disables next critical on initial load when white has no critical moment', () => {
            const states = computeButtonStates({
                mode: 'main',
                url: '/api/load_game',
                hasInitialCriticalForWhite: false,
                learningSide: 'white'
            });
            expect(states.nextCritical).toBe(true);
        });

        it('enables next critical on initial load when white has critical moment', () => {
            const states = computeButtonStates({
                mode: 'main',
                url: '/api/load_game',
                hasInitialCriticalForWhite: true,
                learningSide: 'white'
            });
            expect(states.nextCritical).toBe(false);
        });

        it('disables next critical when no more critical moments found', () => {
            const states = computeButtonStates({
                mode: 'main',
                url: '/game/next_critical_moment',
                serverMessage: 'No further critical moments found for white'
            });
            expect(states.nextCritical).toBe(true);
        });
    });

    describe('variation mode', () => {
        it('disables next critical and fast navigation', () => {
            const states = computeButtonStates({
                mode: 'variation',
                boardExists: true,
                currentVariationPly: 1,
                variationSANs: ['e5', 'Rc5', 'Qf4']
            });
            expect(states.nextCritical).toBe(true);
            expect(states.fastRewind).toBe(true);
            expect(states.fastForward).toBe(true);
            expect(states.resumeGame).toBe(false);
            expect(states.nextMove).toBe(false);
        });

        it('disables next move at end of variation', () => {
            const states = computeButtonStates({
                mode: 'variation',
                currentVariationPly: 2,
                variationSANs: ['e5', 'Rc5']
            });
            expect(states.nextMove).toBe(true);
        });
    });

    describe('postCorrectGuess mode', () => {
        it('uses variationNextArrayIndex for next move disabled state', () => {
            const states = computeButtonStates({
                mode: 'postCorrectGuess',
                currentVariationPly: 1,
                variationSANs: ['e5', 'Rc5', 'Qf4', 'Nd2'],
                variationSANsStartIndex: 0
            });
            expect(states.nextMove).toBe(false);
            expect(states.nextCritical).toBe(true);
            expect(states.resumeGame).toBe(false);
        });

        it('disables next move when variation is exhausted', () => {
            const states = computeButtonStates({
                mode: 'postCorrectGuess',
                currentVariationPly: 4,
                variationSANs: ['e5', 'Rc5', 'Qf4', 'Nd2'],
                variationSANsStartIndex: 0
            });
            expect(states.nextMove).toBe(true);
        });
    });

    describe('declineCritical mode', () => {
        it('re-enables main line navigation and disables resume', () => {
            const states = computeButtonStates({ mode: 'declineCritical' });
            expect(states).toEqual({
                nextCritical: false,
                prevMove: false,
                nextMove: false,
                fastRewind: false,
                fastForward: false,
                resumeGame: true,
                copyFen: false,
                flipBoard: false
            });
        });
    });

    describe('initialLoad mode', () => {
        it('enables prev/next and copy on first board init', () => {
            const states = computeButtonStates({
                mode: 'initialLoad',
                hasInitialCriticalForWhite: true,
                learningSide: 'white',
                inVariationMode: false
            });
            expect(states.prevMove).toBe(false);
            expect(states.nextMove).toBe(false);
            expect(states.copyFen).toBe(false);
            expect(states.flipBoard).toBe(false);
            expect(states.nextCritical).toBe(false);
        });
    });
});
