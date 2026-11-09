// library.js - Handles game library display and upload

import { initializeUpload } from './upload.js';
import { fetchSessionInfo, ownerControls, renderAccountControl } from './session_info.js';

document.addEventListener("DOMContentLoaded", async () => {
    const info = await fetchSessionInfo();
    const controls = ownerControls(info);
    renderAccountControl(document.getElementById('account-control'), controls.account);
    document.getElementById('analysis-resume').hidden = !info.analysis;

    // Anyone may analyze a game; only the owner's analyses are saved, into the
    // library, which only the owner sees.
    initializeUpload(() => loadGameLibrary(), { saveToLibrary: controls.saveToLibrary });
    if (controls.showLibrary) {
        document.getElementById('upload-instructions').textContent =
            'Paste a game in PGN format and click the button to analyze it. The analyzed game is saved to your library.';
        document.getElementById('game-library').hidden = false;
        loadGameLibrary();
    }
});

/**
 * Load and display the game library
 */
async function loadGameLibrary() {
    const gameList = document.getElementById('game-list');
    const loadingMessage = document.getElementById('game-list-loading');
    const errorMessage = document.getElementById('game-list-error');

    // Show loading state
    loadingMessage.style.display = 'block';
    errorMessage.style.display = 'none';
    gameList.replaceChildren();

    try {
        const response = await fetch('/api/pgn_files');
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();

        loadingMessage.style.display = 'none';

        if (!Array.isArray(data) || data.length === 0) {
            const empty = document.createElement('li');
            empty.className = 'info-message';
            empty.textContent = 'No games found. Analyze a game to get started!';
            gameList.append(empty);
            return;
        }

        // Display games as a list. Names come from PGN tags: text only, never HTML.
        gameList.append(...data.map(gameListItem));

    } catch (error) {
        console.error('Failed to load game library:', error);
        loadingMessage.style.display = 'none';
        errorMessage.textContent = `Error loading games: ${error.message}`;
        errorMessage.style.display = 'block';
    }
}

/**
 * A list item linking to a library game.
 * @param {Object} game - The game object from /api/pgn_files
 * @returns {HTMLLIElement}
 */
function gameListItem(game) {
    const link = document.createElement('a');
    link.href = `/game?id=${encodeURIComponent(game.id)}`;
    const name = document.createElement('span');
    name.className = 'game-name';
    name.textContent = formatGameNameFromHeaders(game);
    const meta = document.createElement('span');
    meta.className = 'game-meta';
    meta.textContent = '→';
    link.append(name, meta);
    const item = document.createElement('li');
    item.append(link);
    return item;
}

/**
 * Format a game name from PGN header information
 * @param {Object} game - The game object with white, black, date, and name properties
 * @returns {string} Formatted display name
 */
function formatGameNameFromHeaders(game) {
    // Fallback to filename if no header information is available
    if ((!game.white && !game.black) && game.name) {
        return formatGameName(game.name);
    }

    const white = game.white || 'Unknown';
    const black = game.black || 'Unknown';
    const date = game.date || '';

    // Format date if available (convert "2025.08.06" to "2025-08-06" or keep as is)
    let formattedDate = '';
    if (date) {
        // Handle various date formats
        formattedDate = date.replace(/\./g, '-');
        // If date is in YYYY.MM.DD format, we might want to format it differently
        // For now, just replace dots with dashes
    }

    // Build display name: "White vs Black" or "White vs Black - Date"
    let displayName = `${white} vs ${black}`;
    if (formattedDate) {
        displayName += ` - ${formattedDate}`;
    }

    return displayName;
}

/**
 * Format a filename into a readable game name (fallback)
 * @param {string} filename - The PGN filename
 * @returns {string} Formatted display name
 */
function formatGameName(filename) {
    // Remove .pgn extension
    let name = filename.replace(/\.pgn$/i, '');

    // Replace underscores and hyphens with spaces
    name = name.replace(/[_-]/g, ' ');

    // Capitalize words
    name = name.replace(/\b\w/g, char => char.toUpperCase());

    return name;
}
