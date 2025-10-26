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

        if (!data.pgn_files || data.pgn_files.length === 0) {
            gameList.innerHTML = '<li class="info-message">No games found. Upload a PGN file to get started!</li>';
            return;
        }

        // Display games as a list
        gameList.innerHTML = data.pgn_files.map(filename => {
            // Extract game info from filename if possible
            const displayName = formatGameName(filename);

            return `
                <li>
                    <a href="/game?file=${encodeURIComponent(filename)}">
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
 * Format a filename into a readable game name
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
