// upload.js - Handles PGN text upload and annotation

/**
 * Initialize upload functionality
 * @param {Function} onUploadComplete - Callback when upload completes successfully
 */
export function initializeUpload(onUploadComplete) {
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
            await uploadAndAnalyzePGN(pgnContent, {
                onProgress: updateProgress,
                onStatusChange: updateStatus
            });

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

    function updateStatus(message, type = 'info') {
        uploadStatus.textContent = message;
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
 * Upload and analyze PGN text
 * @param {string} pgnContent - The PGN text content
 * @param {Object} callbacks - Callbacks for progress and status updates
 * @returns {Promise<Object>} - Result of the upload
 */
async function uploadAndAnalyzePGN(pgnContent, callbacks = {}) {
    const { onProgress, onStatusChange } = callbacks;

    // Extract a filename from the PGN content or generate one
    const filename = generateFilename(pgnContent);

    // Update status: validating
    if (onProgress) onProgress(10, 'Validating PGN...');
    if (onStatusChange) onStatusChange('Validating PGN...', 'info');

    // Update status: uploading
    if (onProgress) onProgress(30, 'Sending to server...');
    if (onStatusChange) onStatusChange('Sending to server...', 'info');

    // Send to server for analysis
    const response = await fetch('/api/analyze_and_save', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            pgn_content: pgnContent,
            filename: filename
        })
    });

    if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Upload failed');
    }

    // Update status: annotating
    if (onProgress) onProgress(60, 'Analyzing game...');
    if (onStatusChange) onStatusChange('Analyzing game (this may take a while)...', 'info');

    const result = await response.json();

    // Update status: complete
    if (onProgress) onProgress(100, 'Complete!');
    if (onStatusChange) {
        onStatusChange(
            `Success! Game analyzed and saved as ${result.filename}`,
            'success'
        );
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
