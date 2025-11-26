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

    // Start progress animation that asymptotically approaches 98% over 10 seconds
    const startTime = Date.now();
    const duration = 10000; // 10 seconds
    const targetPercent = 98;
    let animationActive = true;

    const updateProgressAnimation = () => {
        if (!animationActive) return;

        const elapsed = Date.now() - startTime;
        // Asymptotic function: approaches targetPercent as elapsed approaches duration
        // Using exponential approach: percent = target * (1 - e^(-t/duration))
        const t = Math.min(elapsed / duration, 1); // Clamp to 1
        const percent = targetPercent * (1 - Math.exp(-3 * t)); // -3 gives good curve shape

        // Ensure we don't exceed targetPercent
        const clampedPercent = Math.min(percent, targetPercent);

        if (onProgress) {
            onProgress(clampedPercent, 'Analyzing game (this may take a while)...');
        }

        // Continue animation if we haven't reached the target
        if (clampedPercent < targetPercent) {
            requestAnimationFrame(updateProgressAnimation);
        }
    };

    // Update status: analyzing
    if (onStatusChange) onStatusChange('Analyzing game', 'info');
    if (onProgress) onProgress(2, 'Analysis may take a while...'); // Start at 2%

    // Start the progress animation
    requestAnimationFrame(updateProgressAnimation);

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

    // Stop the animation when response arrives
    animationActive = false;

    if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Upload failed');
    }

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
