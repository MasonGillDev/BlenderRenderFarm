#!/bin/bash

# Stop all Blender Render services

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "Stopping Blender Render Services..."

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# Stop Flask, Celery, and Frontend processes
echo "Stopping Flask, Celery, and Frontend server..."
pkill -f "python app.py" && echo -e "${GREEN}✓ Flask stopped${NC}" || echo -e "${YELLOW}✓ Flask not running${NC}"
pkill -f "celery -A tasks worker" && echo -e "${GREEN}✓ Celery stopped${NC}" || echo -e "${YELLOW}✓ Celery not running${NC}"
pkill -f "python -m http.server 3000" && echo -e "${GREEN}✓ Frontend stopped${NC}" || echo -e "${YELLOW}✓ Frontend not running${NC}"

# Ask about stopping Redis service
echo ""
echo -e "${YELLOW}Redis is running as a system service.${NC}"
read -p "Stop Redis service? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    $SUDO_CMD systemctl stop redis-server
    echo -e "${GREEN}✓ Redis stopped${NC}"
else
    echo "Redis service left running"
fi

echo ""
echo -e "${GREEN}Application services stopped successfully!${NC}"
