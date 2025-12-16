#!/bin/bash

# Stop all Blender Render services

echo "Stopping Blender Render Services..."

# Stop Flask and Celery processes
echo "Stopping Flask and Celery..."
pkill -f "python app.py"
pkill -f "celery -A tasks worker"

# Stop Docker containers
echo "Stopping Redis..."
docker-compose down

echo ""
echo "All services stopped successfully!"
