// upload.js - Handles PGN file upload and annotation

/**
 * Initialize upload functionality
 * @param {Function} onUploadComplete - Callback when upload completes successfully
 */
export function initializeUpload(onUploadComplete) {
    const fileInput = document.getElementById('pgn-file-input');
    const chooseFileButton = document.getElementById('choose-file-button');
    const uploadButton = document.getElementById('upload-annotate-button');
    const selectedFileName = document.getElementById('selected-file-name');
    const uploadStatus = document.getElementById('upload-status');
    const uploadProgress = document.getElementById('upload-progress');
    const progressBarFill = document.getElementById('progress-bar-fill');
    const progressText = document.getElementById('progress-text');

    let selectedFile = null;

    // Choose file button click
    chooseFileButton.addEventListener('click', () => {
        fileInput.click();
    });

    // File selection
    fileInput.addEventListener('change', (event) => {
        const file = event.target.files[0];
        if (file) {
            selectedFile = file;
            selectedFileName.textContent = file.name;
            uploadButton.disabled = false;
            clearStatus();
        } else {
            selectedFile = null;
            selectedFileName.textContent = '';
            uploadButton.disabled = true;
        }
    });

    // Upload and annotate button click
    uploadButton.addEventListener('click', async () => {
        if (!selectedFile) return;

        try {
            await uploadAndAnnotatePGN(selectedFile, {
                onProgress: updateProgress,
                onStatusChange: updateStatus
            });

            // Success - call the completion callback
            if (onUploadComplete) {
                onUploadComplete();
            }
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
 * Upload and annotate a PGN file
 * @param {File} file - The PGN file to upload
 * @param {Object} callbacks - Callbacks for progress and status updates
 * @returns {Promise<Object>} - Result of the upload
 */
async function uploadAndAnnotatePGN(file, callbacks = {}) {
    const { onProgress, onStatusChange } = callbacks;

    // Update status: reading file
    if (onProgress) onProgress(10, 'Reading file...');
    if (onStatusChange) onStatusChange('Reading file...', 'info');

    const pgnContent = await readFileAsText(file);

    // Update status: uploading
    if (onProgress) onProgress(30, 'Uploading to server...');
    if (onStatusChange) onStatusChange('Uploading to server...', 'info');

    // Send to server for annotation
    const response = await fetch('/api/annotate_and_save', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            pgn_content: pgnContent,
            filename: file.name
        })
    });

    if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || 'Upload failed');
    }

    // Update status: annotating
    if (onProgress) onProgress(60, 'Annotating with Stockfish...');
    if (onStatusChange) onStatusChange('Annotating with Stockfish (this may take a while)...', 'info');

    const result = await response.json();

    // Update status: complete
    if (onProgress) onProgress(100, 'Complete!');
    if (onStatusChange) {
        onStatusChange(
            `Success! Game annotated and saved as ${result.filename}`,
            'success'
        );
    }

    return result;
}

/**
 * Read a file as text
 * @param {File} file - The file to read
 * @returns {Promise<string>} - File contents as text
 */
function readFileAsText(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = (event) => resolve(event.target.result);
        reader.onerror = (error) => reject(error);
        reader.readAsText(file);
    });
}
