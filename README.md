# Blender Render Service

A web-based application for rendering Blender files on a server with NVIDIA GPU acceleration. Users can upload `.blend` files through a drag-and-drop interface, and the server will render them using headless Blender with Celery task queue management.

## Features

- **Drag & Drop Interface**: Easy-to-use web UI for uploading `.blend` files
- **GPU Acceleration**: NVIDIA CUDA/OptiX support for fast rendering
- **Multiple Output Formats**: PNG, JPEG, OpenEXR, and MP4 (animations)
- **Task Queue**: Redis and Celery for handling multiple concurrent render jobs
- **Real-time Progress**: Live updates on render status
- **Customizable Settings**: Configure samples, resolution, and frame ranges
- **Job History**: View and download previous renders

## Architecture

```
┌─────────────┐
│   Frontend  │ (Vanilla JS/HTML/CSS)
│  (Browser)  │
└──────┬──────┘
       │ HTTP/REST API
┌──────▼──────┐
│    Flask    │ (Python Backend)
│   Server    │
└──────┬──────┘
       │
       ├─────► Redis (Message Broker)
       │
       ├─────► Celery Worker(s)
       │            │
       │            ▼
       │       Blender (Headless)
       │            │
       │            ▼
       └─────► NVIDIA GPU
```

## Prerequisites

### System Requirements

- **OS**: Linux (Ubuntu 20.04+ recommended)
- **GPU**: NVIDIA GPU with CUDA support
- **Memory**: 8GB+ RAM recommended
- **Storage**: Varies based on render output

### Software Requirements

- Python 3.8+
- Docker and Docker Compose
- Blender (headless version)
- NVIDIA GPU drivers
- NVIDIA CUDA Toolkit (for GPU rendering)

## Installation

### 1. Install Blender (Headless)

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install blender

# For a specific version or headless build, download from:
# https://www.blender.org/download/

# Verify installation
blender --version
```

### 2. Install NVIDIA Drivers and CUDA

```bash
# Check if NVIDIA driver is installed
nvidia-smi

# If not installed, follow NVIDIA's official guide:
# https://docs.nvidia.com/cuda/cuda-installation-guide-linux/

# For Ubuntu:
sudo apt install nvidia-driver-535  # or latest version
sudo apt install nvidia-cuda-toolkit
```

### 3. Clone and Setup Project

```bash
# Clone the repository (or download the project)
cd /path/to/BlenderRender

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install -r requirements.txt
```

### 4. Install Docker and Docker Compose

```bash
# Ubuntu
sudo apt install docker.io docker-compose

# Add user to docker group
sudo usermod -aG docker $USER

# Restart session for group changes to take effect
# Then verify
docker --version
docker-compose --version
```

### 5. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit .env and set your configuration
nano .env
```

Important environment variables:

```bash
BLENDER_PATH=/usr/bin/blender  # Path to Blender executable
GPU_TYPE=OPTIX                  # CUDA or OPTIX (OPTIX for RTX cards)
SECRET_KEY=your-secret-key      # Change this!
```

### 6. Verify GPU Configuration

Test if Blender can use your GPU:

```bash
blender -b --python-expr "
import bpy
prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'CUDA'
prefs.get_devices()
print('Available devices:')
for device in prefs.devices:
    print(f'  {device.name}: {device.type}')
"
```

## Running the Application

### Option 1: Using the Start Script (Recommended)

```bash
# Make scripts executable
chmod +x start_services.sh stop_services.sh

# Start all services
./start_services.sh
```

This will start:
- Redis (via Docker)
- Celery worker
- Flask API server

### Option 2: Manual Start

```bash
# Terminal 1: Start Redis
docker-compose up

# Terminal 2: Start Celery worker
cd backend
source ../venv/bin/activate
celery -A tasks worker --loglevel=info --concurrency=2

# Terminal 3: Start Flask API
cd backend
source ../venv/bin/activate
python app.py
```

### Access the Application

1. **Frontend**: Open `frontend/index.html` in your browser
   - Or serve it with a simple HTTP server:
     ```bash
     cd frontend
     python -m http.server 8080
     ```
   - Then visit: `http://localhost:8080`

2. **API**: `http://localhost:5000/api/health`

3. **Redis Commander** (optional monitoring): `http://localhost:8081`

## Usage

### Web Interface

1. Open the frontend in your browser
2. Drag and drop a `.blend` file or click to browse
3. Configure render settings:
   - **Format**: PNG, JPEG, OpenEXR, or MP4 (animation)
   - **Samples**: Quality setting (higher = better quality, slower)
   - **Resolution**: Output image/video dimensions
   - **Animation**: Set frame range for MP4 output
4. Click "Upload & Render"
5. Monitor progress in real-time
6. Download the result when complete

### API Endpoints

#### Upload and Render

```bash
POST /api/upload

# Example with curl
curl -X POST http://localhost:5000/api/upload \
  -F "file=@scene.blend" \
  -F "format=PNG" \
  -F "samples=128" \
  -F "resolution_x=1920" \
  -F "resolution_y=1080"
```

#### Check Status

```bash
GET /api/status/<task_id>

# Example
curl http://localhost:5000/api/status/abc-123-task-id
```

#### Download Result

```bash
GET /api/download/<job_id>

# Example
curl -O http://localhost:5000/api/download/xyz-789-job-id
```

#### List Jobs

```bash
GET /api/jobs

# Example
curl http://localhost:5000/api/jobs
```

## Configuration

### Render Settings

Edit `backend/config.py` to change defaults:

```python
DEFAULT_SAMPLES = 128          # Render samples
DEFAULT_RESOLUTION_X = 1920    # Width
DEFAULT_RESOLUTION_Y = 1080    # Height
MAX_CONTENT_LENGTH = 500 * 1024 * 1024  # Max file size
```

### GPU Settings

For **RTX 20-series and newer** (recommended):
```bash
GPU_TYPE=OPTIX  # Faster ray tracing
```

For **older NVIDIA GPUs**:
```bash
GPU_TYPE=CUDA
```

### Celery Workers

Adjust concurrency based on your system:

```bash
# In start_services.sh or manual start
celery -A tasks worker --concurrency=4  # 4 concurrent renders
```

Warning: More concurrent renders = more GPU/RAM usage

## Project Structure

```
BlenderRender/
├── backend/
│   ├── app.py              # Flask application
│   ├── tasks.py            # Celery tasks
│   ├── render_script.py    # Blender Python script
│   ├── config.py           # Configuration
│   └── uploads/            # Temporary upload directory
├── frontend/
│   ├── index.html          # Web interface
│   ├── styles.css          # Styling
│   └── app.js              # Frontend logic
├── rendered/               # Output directory
├── requirements.txt        # Python dependencies
├── docker-compose.yml      # Redis configuration
├── .env.example            # Environment template
├── start_services.sh       # Startup script
├── stop_services.sh        # Shutdown script
└── README.md              # This file
```

## Troubleshooting

### Blender Can't Find GPU

```bash
# Check NVIDIA driver
nvidia-smi

# Reinstall CUDA toolkit
sudo apt install nvidia-cuda-toolkit

# Test Blender GPU access
blender -b --python-expr "import bpy; print(bpy.context.preferences.addons['cycles'].preferences.devices)"
```

### Celery Worker Not Starting

```bash
# Check Redis connection
redis-cli ping  # Should return "PONG"

# Check logs
celery -A tasks worker --loglevel=debug
```

### Permission Errors

```bash
# Ensure directories are writable
chmod -R 755 backend/uploads rendered

# Check Docker permissions
sudo usermod -aG docker $USER
```

### Out of Memory

- Reduce `DEFAULT_SAMPLES` in config.py
- Reduce Celery concurrency
- Limit resolution settings
- Ensure GPU has sufficient VRAM

## Production Deployment

### Security Considerations

1. Change `SECRET_KEY` in `.env`
2. Set `FLASK_ENV=production`
3. Use nginx as reverse proxy
4. Enable HTTPS
5. Implement authentication
6. Set up rate limiting
7. Configure firewall rules

### Example Nginx Configuration

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location /api {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location / {
        root /path/to/BlenderRender/frontend;
        try_files $uri $uri/ /index.html;
    }
}
```

### Systemd Service

Create `/etc/systemd/system/blender-render.service`:

```ini
[Unit]
Description=Blender Render Service
After=network.target redis.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/path/to/BlenderRender/backend
Environment="PATH=/path/to/BlenderRender/venv/bin"
ExecStart=/path/to/BlenderRender/venv/bin/python app.py
Restart=always

[Install]
WantedBy=multi-user.target
```

## Performance Tips

1. **Use OPTIX** on RTX cards (20-series+) for 2-3x speed improvement
2. **Adjust samples** based on scene complexity (64-256 typical)
3. **Scale workers** based on GPU VRAM (1-2 per GPU recommended)
4. **Use EXR** for professional workflows, PNG for general use
5. **Enable denoising** in Blender scenes for lower sample counts

## License

This project is provided as-is for educational and commercial use.

## Support

For issues, questions, or contributions:
- Check the troubleshooting section
- Review Blender's official documentation
- Check Celery and Flask documentation

## Acknowledgments

- Blender Foundation for the amazing open-source 3D software
- NVIDIA for GPU acceleration support
- Flask, Celery, and Redis communities
# BlenderRenderFarm
