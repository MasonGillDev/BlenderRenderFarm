# Blender Render Farm Setup Guide

## Prerequisites

Before setting up the Blender Render Farm, ensure you have the following installed:

1. **Python 3.12+** - Required for running the Flask backend
2. **Docker** - Required for running Redis
3. **Docker Compose v2** - For orchestrating Docker containers
4. **Blender with GPU Support** - Required for GPU rendering (see GPU Setup section below)
5. **Unrar** (Optional) - Required for RAR archive support
   ```bash
   sudo apt install unrar  # Ubuntu/Debian
   ```
6. **Sufficient Disk Space** - The system now supports files up to 50GB

## Initial Setup Issues & Solutions

### Problem 1: Missing Dependencies
When running `./start_services.sh`, you may encounter:
- `docker-compose: command not found`
- `celery: command not found`
- `python: command not found`

### Solution: Complete Setup Process

#### Step 1: Create Python Virtual Environment
```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Install Python dependencies
pip install -r requirements.txt
```

#### Step 2: Fix Docker Compose Command
The script uses the old `docker-compose` command. Modern Docker uses `docker compose` (with a space).

**Fix applied to `start_services.sh`:**
```bash
# Changed from:
docker-compose up -d

# To:
docker compose up -d
```

#### Step 3: Start Services Properly

Since the automated script may fail, here's how to start services manually:

##### Option A: Manual Start (Recommended for troubleshooting)

1. **Start Redis with Docker:**
```bash
docker compose up -d
```

2. **Start Flask Backend (Terminal 1):**
```bash
cd backend
source ../venv/bin/activate
python app.py
```
The Flask API will be available at http://localhost:5000

3. **Start Celery Worker (Terminal 2):**
```bash
cd backend
source ../venv/bin/activate
celery -A tasks worker --loglevel=info --concurrency=2
```

##### Option B: Using the Start Script (After fixes)
```bash
./start_services.sh
```

## Verifying Services

### Check if all services are running:

1. **Flask API:** 
   ```bash
   curl -I http://localhost:5000/api/upload
   ```
   Should return HTTP 405 (Method Not Allowed) since it expects POST

2. **Redis:**
   ```bash
   docker ps
   ```
   Should show `blender-redis` container running

3. **Redis Commander (Web UI):**
   Open http://localhost:8081 in your browser

## Accessing the Frontend

Once all backend services are running:

### Linux:
```bash
xdg-open frontend/index.html
```

### macOS:
```bash
open frontend/index.html
```

### Windows:
```bash
start frontend/index.html
```

Or manually open in your browser:
`file:///[full-path-to-project]/frontend/index.html`

## Service URLs

- **Frontend:** `file:///path/to/BlenderRenderFarm-main/frontend/index.html`
- **Flask API:** http://localhost:5000
- **Redis Commander:** http://localhost:8081

## Troubleshooting

### "NetworkError when attempting to fetch resource"
This error occurs when the frontend cannot connect to the backend. Ensure:
1. Flask is running on port 5000
2. Check Flask console for any errors
3. Verify CORS is enabled (should be configured in Flask-CORS)

### Docker not running
```bash
# Check Docker status
docker info

# Start Docker daemon (Linux)
sudo systemctl start docker

# For Docker Desktop, start the application
```

### Port already in use
```bash
# Find process using port 5000
lsof -i :5000

# Kill the process
kill -9 [PID]
```

### Celery not connecting to Redis
Ensure Redis is running:
```bash
docker ps | grep redis
```

## Stopping Services

### Manual Stop:
1. Press `Ctrl+C` in Flask terminal
2. Press `Ctrl+C` in Celery terminal
3. Stop Redis:
   ```bash
   docker compose down
   ```

### Using Stop Script:
```bash
./stop_services.sh
```

## Dependencies Installed

The following Python packages are installed via `requirements.txt`:

- **Flask 3.0.0** - Web framework for the API
- **Flask-CORS 4.0.0** - Cross-Origin Resource Sharing support
- **Celery 5.3.4** - Distributed task queue for rendering jobs
- **Redis 5.0.1** - Python client for Redis
- **python-dotenv 1.0.0** - Environment variable management
- **Werkzeug 3.0.1** - WSGI utility library

## Project Structure

```
BlenderRenderFarm-main/
├── backend/
│   ├── app.py          # Flask API server
│   └── tasks.py        # Celery task definitions
├── frontend/
│   ├── index.html      # Main UI
│   ├── app.js          # Frontend logic
│   └── styles.css      # Styling
├── docker-compose.yml   # Redis container configuration
├── requirements.txt     # Python dependencies
├── start_services.sh    # Service startup script
└── venv/               # Python virtual environment (created during setup)
```

## GPU Setup for NVIDIA GPUs (CUDA/OptiX)

### Important: System Blender vs Official Blender

The Blender package from Ubuntu/Debian repositories (`apt install blender`) typically does NOT include CUDA support, even if you have NVIDIA drivers installed. To use GPU rendering with your NVIDIA GPU, you must download the official Blender from blender.org.

**Note:** Blender 5.0 is now available with improved GPU support, better compatibility with modern file formats, and enhanced rendering performance.

### Step 1: Verify NVIDIA Drivers
```bash
# Check if NVIDIA drivers are installed and GPU is detected
nvidia-smi
```

You should see your GPU listed (e.g., RTX 4090, RTX 3080, etc.). If not, install NVIDIA drivers first.

### Step 2: Download Official Blender with CUDA Support
```bash
# Download Blender 5.0 (latest version with full GPU support)
wget https://mirrors.ocf.berkeley.edu/blender/release/Blender5.0/blender-5.0.0-linux-x64.tar.xz

# Extract the archive
tar -xf blender-5.0.0-linux-x64.tar.xz
```

### Step 3: Update Configuration
Edit `backend/config.py` to point to the official Blender:

```python
# Replace the default path with your extracted Blender path
BLENDER_PATH = '/path/to/blender-5.0.0-linux-x64/blender'

# Enable GPU rendering
USE_GPU = True

# Use OPTIX for RTX cards (faster) or CUDA for other NVIDIA GPUs
GPU_TYPE = 'OPTIX'  # or 'CUDA'
```

### Step 4: Verify GPU Detection
Test if Blender can see your GPU:
```bash
/path/to/blender-5.0.0-linux-x64/blender -b -P -c "import bpy; prefs = bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type = 'CUDA'; prefs.get_devices(); print([d.name for d in prefs.devices if d.type == 'CUDA'])"
```

You should see your GPU name(s) in the output.

### Troubleshooting GPU Issues

#### GPU Not Detected
- **Issue:** Blender shows only CPU devices
- **Solution:** You're likely using system Blender without CUDA support. Download official Blender from blender.org

#### Version Compatibility Issues
- **Issue:** Crashes or errors when rendering files from different Blender versions
- **Cause:** Files created in newer Blender versions (4.3+, 5.0+) may have features not available in older versions
- **Solution:** Use Blender 5.0 for maximum compatibility with modern files

#### Pink/Missing Textures in Renders
- **Issue:** Rendered images are pink (missing textures)
- **Cause:** Textures not found when rendering extracted ZIP/RAR files
- **Solution:** The render script automatically searches for textures in the same directory as the .blend file

#### OptiX vs CUDA
- **OptiX:** Faster on RTX cards (20xx series and newer), includes AI denoising
- **CUDA:** Compatible with all NVIDIA GPUs, slightly slower than OptiX on RTX cards

## Notes

- The application runs in development mode by default
- For production, consider using a production WSGI server like Gunicorn
- GPU rendering requires official Blender from blender.org (not system packages)
- The default configuration uses 2 concurrent Celery workers