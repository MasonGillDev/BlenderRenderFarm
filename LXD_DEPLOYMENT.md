# LXD Container Deployment Guide

This guide covers deploying the Blender Render Farm inside an LXD container.

## Why Native Redis for LXD?

This project uses **native Redis installation** instead of Docker for the following reasons:

1. **Avoids nested container issues** - Running Docker inside LXD can cause overlay filesystem permission errors
2. **Simpler setup** - No need for special LXD security configurations
3. **Better performance** - Direct system installation has less overhead
4. **Easier management** - Redis runs as a standard systemd service

## Architecture for LXD Deployment

```
┌─────────────────────────────────────────┐
│         LXD Container (Ubuntu)          │
│                                         │
│  ┌──────────────┐   ┌──────────────┐  │
│  │   Frontend   │   │    Flask     │  │
│  │ (port 3000)  │   │ (port 5000)  │  │
│  └──────────────┘   └──────────────┘  │
│          │                  │          │
│          └─────────┬────────┘          │
│                    │                   │
│         ┌──────────▼─────────┐        │
│         │  Celery Workers    │        │
│         └──────────┬─────────┘        │
│                    │                   │
│         ┌──────────▼─────────┐        │
│         │  Redis (Native)    │        │
│         │   Systemd Service  │        │
│         └────────────────────┘        │
│                    │                   │
│         ┌──────────▼─────────┐        │
│         │  Blender 5.0       │        │
│         │  with GPU Support  │        │
│         └────────────────────┘        │
└─────────────────────────────────────────┘
```

## Prerequisites

### LXD Container Setup

1. **Create Ubuntu LXD Container**
   ```bash
   # On the LXD host
   lxc launch ubuntu:22.04 blender-render
   ```

2. **Configure for GPU Access (if using NVIDIA GPU)**
   ```bash
   # On the LXD host
   lxc config device add blender-render gpu gpu
   lxc restart blender-render
   ```

3. **Access the Container**
   ```bash
   lxc exec blender-render -- bash
   ```

## Installation

### 1. Inside the LXD Container

Clone or copy the project into the container:

```bash
# If git is not installed
apt update && apt install -y git

# Clone the project
git clone <your-repo-url>
cd BlenderRender
```

### 2. Run the Installation Script

```bash
# Make the script executable
chmod +x install_ubuntu.sh

# Run the installation
./install_ubuntu.sh
```

The installation script will:
- Install Python 3.8+
- Install Redis as a native system service
- Install NVIDIA drivers and CUDA (if GPU detected)
- Download Blender 5.0 with GPU support
- Set up Python virtual environment
- Install all Python dependencies
- Configure everything automatically

### 3. Start the Services

```bash
./start_services.sh
```

This will:
- Verify Redis service is running (start it if needed)
- Start Celery worker
- Start Flask API server
- Start frontend server
- Verify all services are healthy

## Service Management

### Starting Services

```bash
./start_services.sh
```

### Stopping Services

```bash
./stop_services.sh
```

This will stop Flask, Celery, and Frontend. It will ask if you want to stop Redis (usually you can leave it running).

### Manual Service Control

#### Redis
```bash
# Check status
sudo systemctl status redis-server

# Start/stop/restart
sudo systemctl start redis-server
sudo systemctl stop redis-server
sudo systemctl restart redis-server

# Test connection
redis-cli ping
```

#### Celery
```bash
# Manual start (from project directory)
cd backend
source ../venv/bin/activate
celery -A tasks worker --loglevel=info --concurrency=2

# Stop
pkill -f "celery -A tasks worker"
```

#### Flask
```bash
# Manual start (from project directory)
cd backend
source ../venv/bin/activate
python app.py

# Stop
pkill -f "python app.py"
```

## Accessing the Application

### From the LXD Host

1. **Get the container IP**
   ```bash
   lxc list
   ```

2. **Access the services**
   - Frontend: `http://<container-ip>:3000`
   - API: `http://<container-ip>:5000`

### Port Forwarding (Optional)

Forward container ports to the host:

```bash
# On the LXD host
lxc config device add blender-render flask-proxy proxy \
  listen=tcp:0.0.0.0:5000 connect=tcp:127.0.0.1:5000

lxc config device add blender-render frontend-proxy proxy \
  listen=tcp:0.0.0.0:3000 connect=tcp:127.0.0.1:3000
```

Now you can access the services via the host's IP address.

## GPU Rendering in LXD

### Verify GPU Access

```bash
# Inside the container
nvidia-smi
```

You should see your GPU listed. If not, make sure you've added the GPU device to the container (see Prerequisites).

### Test Blender GPU Detection

```bash
~/blender-5.0.0-linux-x64/blender -b --python-expr "
import bpy
prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'CUDA'
prefs.get_devices()
for device in prefs.devices:
    if device.type == 'CUDA':
        print(f'GPU Found: {device.name}')
"
```

## Troubleshooting

### Redis Not Starting

```bash
# Check logs
sudo journalctl -u redis-server -n 50

# Check if port is in use
sudo lsof -i :6379

# Restart service
sudo systemctl restart redis-server
```

### Celery Can't Connect to Redis

```bash
# Test Redis connection
redis-cli ping

# Should return: PONG

# Check Redis is listening
sudo netstat -tlnp | grep 6379
```

### GPU Not Detected

```bash
# Inside the container, check NVIDIA
nvidia-smi

# If command not found, drivers may not be available
# On LXD host, ensure GPU device is added:
lxc config device add blender-render gpu gpu
lxc restart blender-render
```

### Running as Root Warning

This is normal in LXD containers. Celery will show a warning:

```
You're running the worker with superuser privileges: this is absolutely not recommended!
```

This is acceptable in containerized environments. For production, consider creating a dedicated user.

## Performance Considerations

### LXD Container Resources

Allocate sufficient resources to your container:

```bash
# Set CPU limit (e.g., 8 CPUs)
lxc config set blender-render limits.cpu 8

# Set memory limit (e.g., 16GB)
lxc config set blender-render limits.memory 16GB
```

### Celery Concurrency

Adjust based on your GPU VRAM and CPU cores:

```bash
# In start_services.sh, modify the concurrency:
celery -A tasks worker --loglevel=info --concurrency=4
```

- More concurrency = more simultaneous renders
- But also = more GPU/RAM usage
- Recommended: 1-2 workers per GPU

## Monitoring

### Check Service Status

```bash
# All services
./start_services.sh  # Shows health check

# Individual services
sudo systemctl status redis-server
ps aux | grep celery
ps aux | grep "python app.py"
```

### Redis Monitoring

```bash
# Connect to Redis CLI
redis-cli

# Inside redis-cli:
INFO
PING
KEYS *
```

### View Logs

```bash
# Redis logs
sudo journalctl -u redis-server -f

# Flask/Celery logs
# (These will be in the terminal where you ran start_services.sh)
```

## Benefits of This Setup

✅ **No Docker overhead** - Direct system installation
✅ **Simpler architecture** - Fewer moving parts
✅ **Better compatibility** - No nested container issues
✅ **Easy debugging** - Standard systemd service management
✅ **Automatic startup** - Redis starts with container (if enabled)
✅ **Production ready** - Systemd supervision and logging

## Comparison: Docker vs Native Redis

| Aspect | Docker Redis | Native Redis |
|--------|-------------|--------------|
| Setup in LXD | Complex (requires security.nesting) | Simple (apt install) |
| Overlay FS Issues | Yes, common in LXD | No issues |
| Performance | Slight overhead | Native performance |
| Management | docker compose | systemctl |
| Logs | docker logs | journalctl |
| Auto-start | Depends on container config | systemd |
| Port binding | Manual configuration | Automatic |

## Additional Resources

- [LXD Documentation](https://documentation.ubuntu.com/lxd/en/latest/)
- [Redis Documentation](https://redis.io/docs/)
- [Celery Documentation](https://docs.celeryproject.org/)
- [Blender Documentation](https://docs.blender.org/)
