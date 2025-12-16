#!/bin/bash

# Start services for Blender Render App
# This script starts Redis, Celery worker, and Flask app

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "Starting Blender Render Services..."

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}Note: Running as root (common in LXD containers)${NC}"
    echo -e "${YELLOW}Celery worker will show warnings about running with superuser privileges.${NC}"
    SUDO_CMD=""
    echo ""
else
    SUDO_CMD="sudo"
fi

# Check if Redis is installed
if ! command -v redis-server &> /dev/null; then
    echo -e "${RED}Error: Redis is not installed.${NC}"
    echo "Please run the installation script first: ./install_ubuntu.sh"
    exit 1
fi

# Check if Redis is running, start if not
echo "Checking Redis service..."
if ! $SUDO_CMD systemctl is-active --quiet redis-server; then
    echo "Starting Redis service..."
    $SUDO_CMD systemctl start redis-server
    sleep 2
fi

# Verify Redis is responding
MAX_RETRIES=10
RETRY_COUNT=0

echo "Verifying Redis connection..."
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if redis-cli ping > /dev/null 2>&1; then
        echo -e "${GREEN}Redis is ready!${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for Redis... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 1
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}Error: Redis is not responding${NC}"
    echo "Check Redis status with: sudo systemctl status redis-server"
    echo "Check Redis logs with: sudo journalctl -u redis-server -n 50"
    exit 1
fi

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    echo "Activating virtual environment..."
    source venv/bin/activate
else
    echo -e "${YELLOW}Warning: Virtual environment not found. Using system Python.${NC}"
fi

# Start Celery worker in background
echo "Starting Celery worker..."
cd backend

# Build Celery command (add --uid if not running as root)
CELERY_CMD="celery -A tasks worker --loglevel=info --concurrency=2"
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}Note: Running Celery as root. Consider using --uid option in production.${NC}"
fi

$CELERY_CMD &
CELERY_PID=$!
echo "Celery worker started with PID: $CELERY_PID"

# Give Celery a moment to start
sleep 2

# Check if Celery is still running
if ! kill -0 $CELERY_PID 2>/dev/null; then
    echo -e "${RED}Error: Celery worker failed to start${NC}"
    echo "Check that:"
    echo "  - Virtual environment is activated"
    echo "  - Redis is running (docker ps | grep redis)"
    echo "  - requirements.txt dependencies are installed"
    exit 1
fi

# Start Flask app
echo "Starting Flask application..."
python app.py &
FLASK_PID=$!
echo "Flask app started with PID: $FLASK_PID"

cd ..

# Start frontend server
echo "Starting frontend server..."
cd frontend
python -m http.server 3000 &
FRONTEND_PID=$!
echo "Frontend server started with PID: $FRONTEND_PID"
cd ..

# Give services a moment to start
sleep 2

# Verify services are running
echo ""
echo "Verifying services..."
SERVICES_OK=true

if ! kill -0 $CELERY_PID 2>/dev/null; then
    echo -e "${RED}✗ Celery worker is not running${NC}"
    SERVICES_OK=false
else
    echo -e "${GREEN}✓ Celery worker is running${NC}"
fi

if ! kill -0 $FLASK_PID 2>/dev/null; then
    echo -e "${RED}✗ Flask application is not running${NC}"
    SERVICES_OK=false
else
    echo -e "${GREEN}✓ Flask application is running${NC}"
fi

if ! kill -0 $FRONTEND_PID 2>/dev/null; then
    echo -e "${RED}✗ Frontend server is not running${NC}"
    SERVICES_OK=false
else
    echo -e "${GREEN}✓ Frontend server is running${NC}"
fi

if ! redis-cli ping > /dev/null 2>&1; then
    echo -e "${RED}✗ Redis is not responding${NC}"
    SERVICES_OK=false
else
    echo -e "${GREEN}✓ Redis is running${NC}"
fi

echo ""

if [ "$SERVICES_OK" = false ]; then
    echo -e "${RED}Some services failed to start. Please check the logs above.${NC}"
    exit 1
fi

echo "======================================"
echo "All services started successfully!"
echo "======================================"
echo "Flask API: http://localhost:5000"
echo "Frontend: http://localhost:3000"
echo ""
echo "To stop services, run: ./stop_services.sh"
echo "Or press Ctrl+C to stop Flask and Celery"
echo ""

# Wait for any process to exit
wait -n

# Exit with status of process that exited first
exit $?
