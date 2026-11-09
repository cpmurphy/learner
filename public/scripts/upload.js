// upload.js - Handles PGN text upload and annotation

/**
 * Initialize upload functionality
 * @param {Function} onUploadComplete - Callback when a game is saved to the library
 * @param {{saveToLibrary: boolean}} options - The owner's analyses are saved to the
 *   library; anyone else's live only in their session and open straight away.
 */
export function initializeUpload(onUploadComplete, { saveToLibrary = false } = {}) {
    const textInput = document.getElementById('pgn-text-input');
    const uploadButton = document.getElementById('upload-analyze-button');
    const uploadStatus = document.getElementById('upload-status');
    const uploadProgress = document.getElementById('upload-progress');
    const progressBarFill = document.getElementById('progress-bar-fill');
    const progressText = document.getElementById('progress-text');

    // Upload and analyze button click
    uploadButton.addEventListener('click', async () => {
        const pgnContent = textInput.value.trim();

        if (!pgnContent) {
            updateStatus('Please paste PGN content first.', 'error');
            return;
        }

        clearStatus();

        try {
            const callbacks = { onProgress: updateProgress, onStatusChange: updateStatus };
            if (!saveToLibrary) {
                const result = await analyzeInSession(pgnContent, callbacks);
                window.location.assign(result.game_url);
                return;
            }

            await uploadAndAnalyzePGN(pgnContent, callbacks);

            // Success - call the completion callback
            if (onUploadComplete) {
                onUploadComplete();
            }

            // Clear the textarea after successful upload
            textInput.value = '';
        } catch (error) {
            updateStatus(`Error: ${error.message}`, 'error');
        }
    });

    function updateProgress(percent, message) {
        uploadProgress.style.display = 'block';
        progressBarFill.style.width = `${percent}%`;
        progressText.textContent = message;
    }

    // Messages are text; +link+ ({href, text}) optionally follows them.
    function updateStatus(message, type = 'info', link = null) {
        uploadStatus.textContent = message;
        if (link) {
            const anchor = document.createElement('a');
            anchor.href = link.href;
            anchor.className = 'upload-status-link';
            anchor.textContent = link.text;
            uploadStatus.append(' ', anchor);
        }
        uploadStatus.className = 'upload-status ' + type;
    }

    function clearStatus() {
        uploadStatus.textContent = '';
        uploadStatus.className = 'upload-status';
        uploadProgress.style.display = 'none';
        progressBarFill.style.width = '0%';
        progressText.textContent = '';
    }
}

/**
 * Analyze PGN text without saving it: the server keeps the game in this
 * visitor's session only.
 * @param {string} pgnContent - The PGN text content
 * @param {Object} callbacks - Callbacks for progress and status updates
 * @returns {Promise<{game_url: string}>}
 */
async function analyzeInSession(pgnContent, callbacks = {}) {
    const result = await postForAnalysis('/api/analyze', { pgn_content: pgnContent }, callbacks);
    if (callbacks.onStatusChange) callbacks.onStatusChange('Analysis complete. Opening the game…', 'success');
    return result;
}

/**
 * POST a game for analysis while showing progress.
 * @returns {Promise<Object>} - The server's JSON answer
 */
async function postForAnalysis(url, body, callbacks) {
    const { onProgress, onStatusChange } = callbacks;
    const stopAnimation = startProgressAnimation(onProgress);
    if (onStatusChange) onStatusChange('Analyzing game', 'info');

    let response;
    try {
        response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
    } finally {
        stopAnimation();
    }

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
        throw new Error(data.error || `Analysis failed (HTTP ${response.status})`);
    }
    if (onProgress) onProgress(100, 'Complete!');
    return data;
}

/**
 * Animate the progress bar towards 98% until the returned function is called.
 * @param {Function|undefined} onProgress
 * @returns {Function} stops the animation
 */
function startProgressAnimation(onProgress) {
    const startTime = Date.now();
    const duration = 10000; // 10 seconds
    const targetPercent = 98;
    let animationActive = true;

    const step = () => {
        if (!animationActive) return;
        const t = Math.min((Date.now() - startTime) / duration, 1);
        const percent = Math.min(targetPercent * (1 - Math.exp(-3 * t)), targetPercent);
        if (onProgress) onProgress(percent, 'Analysis may take a while...');
        if (percent < targetPercent) requestAnimationFrame(step);
    };

    if (onProgress) onProgress(2, 'Analysis may take a while...');
    requestAnimationFrame(step);
    return () => { animationActive = false; };
}

/**
 * Upload and analyze PGN text, saving it to the owner's library
 * @param {string} pgnContent - The PGN text content
 * @param {Object} callbacks - Callbacks for progress and status updates
 * @returns {Promise<Object>} - Result of the upload
 */
async function uploadAndAnalyzePGN(pgnContent, callbacks = {}) {
    const { onStatusChange } = callbacks;

    // Extract a filename from the PGN content or generate one
    const filename = generateFilename(pgnContent);
    const result = await postForAnalysis('/api/analyze_and_save', { pgn_content: pgnContent, filename }, callbacks);

    if (onStatusChange) {
        if (result.file_id) {
            onStatusChange('Success! Game analyzed and saved.', 'success',
                { href: `/game?id=${encodeURIComponent(result.file_id)}`, text: 'View completed analysis →' });
        } else {
            onStatusChange(`Success! Game analyzed and saved as ${result.filename}`, 'success');
        }
    }

    return result;
}

/**
 * Generate a filename from PGN content
 * @param {string} pgnContent - The PGN text
 * @returns {string} - Generated filename
 */
function generateFilename(pgnContent) {
    // Try to extract Event and Date tags for a meaningful filename
    const eventMatch = pgnContent.match(/\[Event\s+"([^"]+)"\]/);
    const dateMatch = pgnContent.match(/\[Date\s+"([^"]+)"\]/);
    const whiteMatch = pgnContent.match(/\[White\s+"([^"]+)"\]/);
    const blackMatch = pgnContent.match(/\[Black\s+"([^"]+)"\]/);

    let filename = '';

    // Use White vs Black if available
    if (whiteMatch && blackMatch) {
        const white = sanitizeForFilename(whiteMatch[1]);
        const black = sanitizeForFilename(blackMatch[1]);
        filename = `${white}-vs-${black}`;
    } else if (eventMatch) {
        filename = sanitizeForFilename(eventMatch[1]);
    }

    // Add date if available
    if (dateMatch) {
        const date = dateMatch[1].replace(/\./g, '-');
        filename = filename ? `${filename}-${date}` : date;
    }

    // Fallback to timestamp if nothing found
    if (!filename) {
        const timestamp = new Date().toISOString().slice(0, 19).replace(/:/g, '-');
        filename = `game-${timestamp}`;
    }

    return `${filename}.pgn`;
}

/**
 * Sanitize string for use in filename
 * @param {string} str - String to sanitize
 * @returns {string} - Sanitized string
 */
function sanitizeForFilename(str) {
    return str
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .substring(0, 50);
}
