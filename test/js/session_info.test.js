// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from 'vitest';
import { fetchSessionInfo, ownerControls, renderAccountControl } from '../../public/scripts/session_info.js';

describe('ownerControls', () => {
    it('shows upload and logout to a logged-in owner', () => {
        expect(ownerControls({ owner: true, login_enabled: true })).toEqual({ showUpload: true, account: 'logout' });
    });

    it('shows only the login link to visitors when login is enabled', () => {
        expect(ownerControls({ owner: false, login_enabled: true })).toEqual({ showUpload: false, account: 'login' });
    });

    it('shows upload without account controls in open (development) mode', () => {
        expect(ownerControls({ owner: true, login_enabled: false })).toEqual({ showUpload: true, account: null });
    });

    it('shows nothing when writes are disabled', () => {
        expect(ownerControls({ owner: false, login_enabled: false })).toEqual({ showUpload: false, account: null });
    });
});

describe('fetchSessionInfo', () => {
    afterEach(() => vi.unstubAllGlobals());

    it('returns the server answer', async () => {
        vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ owner: true, login_enabled: true }) }));
        expect(await fetchSessionInfo()).toEqual({ owner: true, login_enabled: true });
    });

    it('treats errors and odd values as an anonymous visitor', async () => {
        vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('offline')));
        expect(await fetchSessionInfo()).toEqual({ owner: false, login_enabled: false });

        vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ owner: 'yes' }) }));
        expect(await fetchSessionInfo()).toEqual({ owner: false, login_enabled: false });
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
