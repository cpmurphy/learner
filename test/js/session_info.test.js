// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from 'vitest';
import { fetchSessionInfo, ownerControls, renderAccountControl } from '../../public/scripts/session_info.js';

describe('ownerControls', () => {
    it('shows the library and logout to a logged-in owner', () => {
        expect(ownerControls({ owner: true, login_enabled: true }))
            .toEqual({ showLibrary: true, saveToLibrary: true, account: 'logout' });
    });

    it('hides the library from visitors, who see the login link when login is enabled', () => {
        expect(ownerControls({ owner: false, login_enabled: true }))
            .toEqual({ showLibrary: false, saveToLibrary: false, account: 'login' });
    });

    it('shows the library without account controls in open (development) mode', () => {
        expect(ownerControls({ owner: true, login_enabled: false }))
            .toEqual({ showLibrary: true, saveToLibrary: true, account: null });
    });

    it('hides the library when there is no owner', () => {
        expect(ownerControls({ owner: false, login_enabled: false }))
            .toEqual({ showLibrary: false, saveToLibrary: false, account: null });
    });
});

describe('fetchSessionInfo', () => {
    afterEach(() => vi.unstubAllGlobals());

    it('returns the server answer', async () => {
        vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ owner: true, login_enabled: true, analysis: true }) }));
        expect(await fetchSessionInfo()).toEqual({ owner: true, login_enabled: true, analysis: true });
    });

    it('treats errors and odd values as an anonymous visitor', async () => {
        vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('offline')));
        expect(await fetchSessionInfo()).toEqual({ owner: false, login_enabled: false, analysis: false });

        vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ owner: 'yes' }) }));
        expect(await fetchSessionInfo()).toEqual({ owner: false, login_enabled: false, analysis: false });
    });
});

describe('renderAccountControl', () => {
    it('renders a login link or a logout form', () => {
        const container = document.createElement('div');
        renderAccountControl(container, 'login');
        expect(container.querySelector('a').getAttribute('href')).toBe('/login.html');

        renderAccountControl(container, 'logout');
        const form = container.querySelector('form');
        expect(form.getAttribute('method')).toBe('post');
        expect(form.getAttribute('action')).toBe('/logout');
        expect(container.querySelector('a')).toBeNull();

        renderAccountControl(container, null);
        expect(container.children.length).toBe(0);
    });
});
