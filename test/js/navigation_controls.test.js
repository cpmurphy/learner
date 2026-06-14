import { describe, it, expect } from 'vitest';
import { NavigationControls } from '../../public/scripts/navigation_controls.js';

const buttonNames = [
    'nextCritical',
    'prevMove',
    'nextMove',
    'fastRewind',
    'fastForward',
    'resumeGame',
    'copyFen',
    'flipBoard'
];

function buildControls() {
    const buttons = Object.fromEntries(buttonNames.map((name) => [name, { disabled: null }]));
    return { buttons, controls: new NavigationControls(buttons) };
}

describe('NavigationControls', () => {
    it('disables all navigation buttons on error', () => {
        const { buttons, controls } = buildControls();
        controls.setError();
        expect(Object.fromEntries(buttonNames.map((name) => [name, buttons[name].disabled]))).toEqual({
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

    it('enables main-line navigation when not at the end', () => {
        const { buttons, controls } = buildControls();
        controls.setBoardExists(true);
        controls.setMain({ moveIndex: 5, totalPositions: 40 });
        expect(buttons.nextMove.disabled).toBe(false);
        expect(buttons.fastRewind.disabled).toBe(false);
        expect(buttons.fastForward.disabled).toBe(false);
        expect(buttons.resumeGame.disabled).toBe(true);
    });

    it('disables next move and fast forward at the last position', () => {
        const { buttons, controls } = buildControls();
        controls.setBoardExists(true);
        controls.setMain({ moveIndex: 39, totalPositions: 40 });
        expect(buttons.nextMove.disabled).toBe(true);
        expect(buttons.fastForward.disabled).toBe(true);
    });

    it('disables fast rewind at the start', () => {
        const { buttons, controls } = buildControls();
        controls.setBoardExists(true);
        controls.setMain({ moveIndex: 0, totalPositions: 40 });
        expect(buttons.fastRewind.disabled).toBe(true);
    });

    it('uses initial critical availability for next critical on load', () => {
        const { buttons, controls } = buildControls();
        controls.setLearningSide('white');
        controls.setMain({}, { url: '/api/load_game', hasInitialCriticalForWhite: false });
        expect(buttons.nextCritical.disabled).toBe(true);

        controls.setMain({}, { url: '/api/load_game', hasInitialCriticalForWhite: true });
        expect(buttons.nextCritical.disabled).toBe(false);
    });

    it('disables next critical when no more critical moments are found', () => {
        const { buttons, controls } = buildControls();
        controls.setMain({}, {
            url: '/game/next_critical_moment',
            serverMessage: 'No further critical moments found for white'
        });
        expect(buttons.nextCritical.disabled).toBe(true);
    });

    it('sets variation navigation state', () => {
        const { buttons, controls } = buildControls();
        controls.setBoardExists(true);
        controls.setVariation({ currentPly: 1, sans: ['e5', 'Rc5', 'Qf4'] });
        expect(buttons.nextCritical.disabled).toBe(true);
        expect(buttons.fastRewind.disabled).toBe(true);
        expect(buttons.fastForward.disabled).toBe(true);
        expect(buttons.resumeGame.disabled).toBe(false);
        expect(buttons.nextMove.disabled).toBe(false);
    });

    it('disables next move at the end of a variation', () => {
        const { buttons, controls } = buildControls();
        controls.setVariation({ currentPly: 2, sans: ['e5', 'Rc5'] });
        expect(buttons.nextMove.disabled).toBe(true);
    });

    it('sets post-correct-guess navigation state', () => {
        const { buttons, controls } = buildControls();
        controls.setPostCorrectGuess({ currentPly: 1, sans: ['e5', 'Rc5', 'Qf4', 'Nd2'], startIndex: 0 });
        expect(buttons.nextMove.disabled).toBe(false);
        expect(buttons.nextCritical.disabled).toBe(true);
        expect(buttons.resumeGame.disabled).toBe(false);
    });

    it('re-enables main-line navigation after declining a challenge', () => {
        const { buttons, controls } = buildControls();
        controls.setDeclineCritical();
        expect(Object.fromEntries(buttonNames.map((name) => [name, buttons[name].disabled]))).toEqual({
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

    it('enables core controls on initial load', () => {
        const { buttons, controls } = buildControls();
        controls.setLearningSide('white');
        controls.setInitialLoad({ hasInitialCriticalForWhite: true });
        expect(buttons.prevMove.disabled).toBe(false);
        expect(buttons.nextMove.disabled).toBe(false);
        expect(buttons.copyFen.disabled).toBe(false);
        expect(buttons.flipBoard.disabled).toBe(false);
        expect(buttons.nextCritical.disabled).toBe(false);
    });
});
