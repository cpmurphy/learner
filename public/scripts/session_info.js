// session_info.js - What this visitor may do (owner or not), from /api/session

const ANONYMOUS = Object.freeze({ owner: false, login_enabled: false, analysis: false });

/**
 * Fetch the visitor's session info. Any failure counts as an anonymous visitor.
 * +analysis+ says whether the session holds a game the visitor analyzed.
 * @returns {Promise<{owner: boolean, login_enabled: boolean, analysis: boolean}>}
 */
export async function fetchSessionInfo() {
    try {
        const response = await fetch('/api/session');
        if (!response.ok) return ANONYMOUS;
        const info = await response.json();
        return {
            owner: info.owner === true,
            login_enabled: info.login_enabled === true,
            analysis: info.analysis === true
        };
    } catch {
        return ANONYMOUS;
    }
}

/**
 * Decide which owner controls to show. The library (seeing it, and saving
 * analyzed games into it) is the owner's alone; anyone may analyze a game,
 * which then lives only in their session.
 * @param {{owner: boolean, login_enabled: boolean}} info
 * @returns {{showLibrary: boolean, saveToLibrary: boolean, account: 'login'|'logout'|null}}
 */
export function ownerControls(info) {
    // No password configured: either everyone is the owner (development) or nobody is.
    let account = null;
    if (info.login_enabled) account = info.owner ? 'logout' : 'login';
    return { showLibrary: info.owner, saveToLibrary: info.owner, account };
}

/**
 * Render the login link or logout button into +container+.
 * @param {HTMLElement} container
 * @param {'login'|'logout'|null} account
 */
export function renderAccountControl(container, account) {
    container.replaceChildren();
    if (account === 'login') {
        const link = document.createElement('a');
        link.href = '/login.html';
        link.textContent = 'Owner login';
        container.append(link);
    } else if (account === 'logout') {
        const form = document.createElement('form');
        form.method = 'post';
        form.action = '/logout';
        const button = document.createElement('button');
        button.type = 'submit';
        button.className = 'app-button';
        button.textContent = 'Log out';
        form.append(button);
        container.append(form);
    }
}
