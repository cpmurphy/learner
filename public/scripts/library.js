// library.js - Handles game library display and upload

import { initializeUpload } from './upload.js';

document.addEventListener("DOMContentLoaded", () => {
    loadGameLibrary();

    // Initialize upload functionality with callback to refresh library
    initializeUpload(() => {
        console.log("Upload completed, refreshing game library");
        loadGameLibrary();
    });
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
    gameList.innerHTML = '';

    try {
        const response = await fetch('/api/pgn_files');
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();

        loadingMessage.style.display = 'none';

        if (!Array.isArray(data) || data.length === 0) {
            gameList.innerHTML = '<li class="info-message">No games found. Upload a PGN file to get started!</li>';
            return;
        }

        // Display games as a list
        gameList.innerHTML = data.map(game => {
            // Extract game info from PGN headers
            const displayName = formatGameNameFromHeaders(game);

            return `
                <li>
                    <a href="/game?id=${encodeURIComponent(game.id)}">
                        <span class="game-name">${displayName}</span>
                        <span class="game-meta">→</span>
                    </a>
                </li>
            `;
        }).join('');

    } catch (error) {
        console.error('Failed to load game library:', error);
        loadingMessage.style.display = 'none';
        errorMessage.textContent = `Error loading games: ${error.message}`;
        errorMessage.style.display = 'block';
    }
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
