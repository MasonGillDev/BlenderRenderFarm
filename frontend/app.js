// Configuration
const API_URL = 'http://localhost:5000/api';

// State
let currentJobId = null;
let currentTaskId = null;
let pollInterval = null;

// DOM Elements
const dropZone = document.getElementById('dropZone');
const fileInput = document.getElementById('fileInput');
const browseBtn = document.getElementById('browseBtn');
const renderSettings = document.getElementById('renderSettings');
const formatSelect = document.getElementById('formatSelect');
const animationSettings = document.getElementById('animationSettings');
const uploadBtn = document.getElementById('uploadBtn');
const progressSection = document.getElementById('progressSection');
const progressFill = document.getElementById('progressFill');
const progressText = document.getElementById('progressText');
const jobInfo = document.getElementById('jobInfo');
const resultSection = document.getElementById('resultSection');
const downloadBtn = document.getElementById('downloadBtn');
const newRenderBtn = document.getElementById('newRenderBtn');
const errorSection = document.getElementById('errorSection');
const errorMessage = document.getElementById('errorMessage');
const retryBtn = document.getElementById('retryBtn');
const jobsList = document.getElementById('jobsList');
const refreshJobsBtn = document.getElementById('refreshJobsBtn');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    setupEventListeners();
    loadJobs();
});

function setupEventListeners() {
    // Drag and drop
    dropZone.addEventListener('click', () => fileInput.click());
    browseBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        fileInput.click();
    });

    dropZone.addEventListener('dragover', (e) => {
        e.preventDefault();
        dropZone.classList.add('drag-over');
    });

    dropZone.addEventListener('dragleave', () => {
        dropZone.classList.remove('drag-over');
    });

    dropZone.addEventListener('drop', (e) => {
        e.preventDefault();
        dropZone.classList.remove('drag-over');
        const files = e.dataTransfer.files;
        if (files.length > 0) {
            handleFileSelect(files[0]);
        }
    });

    fileInput.addEventListener('change', (e) => {
        if (e.target.files.length > 0) {
            handleFileSelect(e.target.files[0]);
        }
    });

    // Format selection
    formatSelect.addEventListener('change', (e) => {
        if (e.target.value === 'FFMPEG') {
            animationSettings.classList.remove('hidden');
        } else {
            animationSettings.classList.add('hidden');
        }
    });

    // Buttons
    uploadBtn.addEventListener('click', uploadFile);
    downloadBtn.addEventListener('click', downloadResult);
    newRenderBtn.addEventListener('click', resetUI);
    retryBtn.addEventListener('click', resetUI);
    refreshJobsBtn.addEventListener('click', loadJobs);
}

function handleFileSelect(file) {
    if (!file.name.endsWith('.blend') && !file.name.endsWith('.zip') && !file.name.endsWith('.rar')) {
        showError('Please select a valid .blend, .zip, or .rar file');
        return;
    }

    const fileSizeGB = file.size / (1024 * 1024 * 1024);
    if (fileSizeGB > 50) {
        showError('File size exceeds 50GB limit');
        return;
    }

    fileInput.files = createFileList(file);
    renderSettings.classList.remove('hidden');

    // Update drop zone to show selected file
    const dropText = dropZone.querySelector('.drop-text');
    const fileSizeMB = file.size / (1024 * 1024);
    
    // Display size in GB if over 1GB, otherwise in MB
    let sizeText;
    if (fileSizeGB >= 1) {
        sizeText = `${fileSizeGB.toFixed(2)} GB`;
    } else {
        sizeText = `${fileSizeMB.toFixed(2)} MB`;
    }
    
    dropText.textContent = `Selected: ${file.name} (${sizeText})`;
}

function createFileList(file) {
    const dt = new DataTransfer();
    dt.items.add(file);
    return dt.files;
}

async function uploadFile() {
    const file = fileInput.files[0];
    if (!file) {
        showError('Please select a file first');
        return;
    }

    const formData = new FormData();
    formData.append('file', file);
    formData.append('format', formatSelect.value);
    formData.append('samples', document.getElementById('samplesInput').value);
    formData.append('resolution_x', document.getElementById('resolutionX').value);
    formData.append('resolution_y', document.getElementById('resolutionY').value);

    if (formatSelect.value === 'FFMPEG') {
        formData.append('frame_start', document.getElementById('frameStart').value);
        formData.append('frame_end', document.getElementById('frameEnd').value);
    }

    // Show progress section
    renderSettings.classList.add('hidden');
    progressSection.classList.remove('hidden');
    updateProgress(0, 'Uploading file...');

    try {
        const response = await fetch(`${API_URL}/upload`, {
            method: 'POST',
            body: formData
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.error || 'Upload failed');
        }

        const data = await response.json();
        currentJobId = data.job_id;
        currentTaskId = data.task_id;

        jobInfo.innerHTML = `
            <strong>Job ID:</strong> ${data.job_id}<br>
            <strong>Task ID:</strong> ${data.task_id}<br>
            <strong>Status:</strong> ${data.status}
        `;

        updateProgress(10, 'File uploaded. Queued for rendering...');

        // Start polling for progress
        startPolling();

    } catch (error) {
        showError(error.message);
        progressSection.classList.add('hidden');
        renderSettings.classList.remove('hidden');
    }
}

function startPolling() {
    if (pollInterval) {
        clearInterval(pollInterval);
    }

    pollInterval = setInterval(async () => {
        try {
            const response = await fetch(`${API_URL}/status/${currentTaskId}`);
            const data = await response.json();

            // Enhanced progress display for animations
            if (data.current_frame && data.total_frames) {
                updateProgress(data.progress, data.status);
                
                // Show detailed frame progress
                const progressDetails = document.getElementById('progressDetails');
                progressDetails.innerHTML = `
                    <div style="text-align: center; margin-top: 10px;">
                        <strong>Frame ${data.current_frame} of ${data.total_frames}</strong>
                        <div style="margin-top: 5px; font-size: 0.9em; color: #666;">
                            ${Math.round((data.current_frame / data.total_frames) * 100)}% complete
                        </div>
                    </div>
                `;
            } else {
                updateProgress(data.progress, data.status);
                document.getElementById('progressDetails').innerHTML = '';
            }

            if (data.state === 'SUCCESS') {
                clearInterval(pollInterval);
                showSuccess();
            } else if (data.state === 'FAILURE') {
                clearInterval(pollInterval);
                showError(data.status);
            }

        } catch (error) {
            console.error('Polling error:', error);
        }
    }, 2000); // Poll every 2 seconds
}

function updateProgress(percentage, message) {
    progressFill.style.width = `${percentage}%`;
    progressText.textContent = message;
}

function showSuccess() {
    progressSection.classList.add('hidden');
    resultSection.classList.remove('hidden');
    loadJobs();
}

function showError(message) {
    progressSection.classList.add('hidden');
    errorSection.classList.remove('hidden');
    errorMessage.textContent = message;
}

function downloadResult() {
    if (currentJobId) {
        window.location.href = `${API_URL}/download/${currentJobId}`;
    }
}

function resetUI() {
    // Clear state
    currentJobId = null;
    currentTaskId = null;
    if (pollInterval) {
        clearInterval(pollInterval);
    }

    // Reset file input
    fileInput.value = '';
    const dropText = dropZone.querySelector('.drop-text');
    dropText.textContent = 'Drag & drop your .blend, .zip, or .rar file here';

    // Hide all sections except upload
    renderSettings.classList.add('hidden');
    progressSection.classList.add('hidden');
    resultSection.classList.add('hidden');
    errorSection.classList.add('hidden');

    // Reset progress
    progressFill.style.width = '0%';
    progressText.textContent = '';
    jobInfo.innerHTML = '';
}

async function loadJobs() {
    try {
        const response = await fetch(`${API_URL}/jobs`);
        const data = await response.json();

        if (data.jobs && data.jobs.length > 0) {
            jobsList.innerHTML = data.jobs.map(job => `
                <div class="job-item">
                    <div>
                        <div class="job-id">${job.job_id}</div>
                        <small>${job.file_count} file(s)</small>
                    </div>
                    <button class="job-download" onclick="downloadJob('${job.job_id}')">
                        Download
                    </button>
                </div>
            `).join('');
        } else {
            jobsList.innerHTML = '<p class="no-jobs">No renders yet</p>';
        }
    } catch (error) {
        console.error('Failed to load jobs:', error);
    }
}

function downloadJob(jobId) {
    window.location.href = `${API_URL}/download/${jobId}`;
}
