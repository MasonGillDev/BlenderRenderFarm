#!/bin/bash

# Start services for Blender Render App
# This script starts Redis, Celery worker, and Flask app

echo "Starting Blender Render Services..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Start Redis with Docker Compose
echo "Starting Redis..."
docker compose up -d

# Wait for Redis to be ready
echo "Waiting for Redis to be ready..."
sleep 3

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    echo "Activating virtual environment..."
    source venv/bin/activate
fi

# Start Celery worker in background
echo "Starting Celery worker..."
cd backend
celery -A tasks worker --loglevel=info --concurrency=2 &
CELERY_PID=$!
echo "Celery worker started with PID: $CELERY_PID"

# Start Flask app
echo "Starting Flask application..."
python app.py &
FLASK_PID=$!
echo "Flask app started with PID: $FLASK_PID"

cd ..

echo ""
echo "======================================"
echo "All services started successfully!"
echo "======================================"
echo "Flask API: http://localhost:5000"
echo "Frontend: Open frontend/index.html in your browser"
echo "Redis Commander: http://localhost:8081"
echo ""
echo "To stop services, run: ./stop_services.sh"
echo "Or press Ctrl+C and then run: docker-compose down"
echo ""

# Wait for any process to exit
wait -n

# Exit with status of process that exited first
exit $?
