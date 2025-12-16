#!/bin/bash

# Stop all Blender Render services

echo "Stopping Blender Render Services..."

# Stop Flask, Celery, and Frontend processes
echo "Stopping Flask, Celery, and Frontend server..."
pkill -f "python app.py"
pkill -f "celery -A tasks worker"
pkill -f "python -m http.server 3000"

# Stop Docker containers
echo "Stopping Redis..."
docker-compose down

echo ""
echo "All services stopped successfully!"
