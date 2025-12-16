#!/bin/bash

#####################################################################
# Blender Render Farm - Ubuntu Installation Script
# This script installs all required software for a fresh Ubuntu install
#####################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}======================================"
echo -e "Blender Render Farm Installation"
echo -e "======================================${NC}"
echo ""
echo "This script will install all required software for the Blender Render Farm."
echo "Installation directory: $PROJECT_DIR"
echo ""

# Function to print status messages
print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running on Ubuntu
print_status "Checking operating system..."
if [ ! -f /etc/os-release ]; then
    print_error "Cannot detect operating system"
    exit 1
fi

source /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    print_warning "This script is designed for Ubuntu. Detected: $ID"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
print_success "Running on Ubuntu $VERSION_ID"

# Check if running as root (we'll use sudo when needed)

# Update system
print_status "Updating system packages..."
sudo apt update
sudo apt upgrade -y
print_success "System updated"

#####################################################################
# Install Python 3.12 or latest available
#####################################################################
print_status "Installing Python 3..."

# Check Python version
PYTHON_VERSION=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "0.0.0")
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 8 ]; then
    print_success "Python $PYTHON_VERSION already installed"
else
    sudo apt install -y python3 python3-pip python3-venv python3-dev
    print_success "Python 3 installed"
fi

# Install build essentials for Python packages
print_status "Installing build tools..."
sudo apt install -y build-essential software-properties-common curl wget git
print_success "Build tools installed"

#####################################################################
# Install Docker and Docker Compose v2
#####################################################################
print_status "Installing Docker..."

if command -v docker &> /dev/null; then
    print_success "Docker already installed ($(docker --version))"
else
    # Remove old versions
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Install prerequisites
    sudo apt install -y ca-certificates curl gnupg lsb-release

    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    print_success "Docker installed ($(docker --version))"
fi

# Add user to docker group
print_status "Adding user to docker group..."
sudo usermod -aG docker $USER
print_success "User added to docker group"

# Start and enable Docker service
print_status "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker
print_success "Docker service started and enabled"

# Verify Docker Compose v2
if docker compose version &> /dev/null; then
    print_success "Docker Compose v2 installed ($(docker compose version))"
else
    print_error "Docker Compose v2 not found. Please check Docker installation."
    exit 1
fi

#####################################################################
# Install NVIDIA Drivers and CUDA Toolkit
#####################################################################
print_status "Checking for NVIDIA GPU..."

if lspci | grep -i nvidia &> /dev/null; then
    print_success "NVIDIA GPU detected"

    # Check if nvidia-smi is available
    if command -v nvidia-smi &> /dev/null; then
        print_success "NVIDIA drivers already installed ($(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1))"
    else
        print_warning "NVIDIA GPU detected but drivers not installed"
        echo ""
        echo "NVIDIA driver installation options:"
        echo "1. Automatic installation (recommended driver)"
        echo "2. Skip and install manually later"
        read -p "Choose option (1-2): " -n 1 -r NVIDIA_CHOICE
        echo ""

        if [[ $NVIDIA_CHOICE == "1" ]]; then
            print_status "Installing NVIDIA drivers..."

            # Add graphics drivers PPA
            sudo add-apt-repository -y ppa:graphics-drivers/ppa
            sudo apt update

            # Install recommended driver
            sudo ubuntu-drivers install

            print_success "NVIDIA drivers installed"
            print_warning "System reboot required for drivers to take effect"
            print_warning "After reboot, run this script again to complete installation"
        else
            print_warning "Skipping NVIDIA driver installation"
            print_warning "GPU rendering will not work until drivers are installed"
        fi
    fi

    # Install CUDA Toolkit
    if command -v nvidia-smi &> /dev/null; then
        print_status "Installing CUDA Toolkit..."

        if command -v nvcc &> /dev/null; then
            print_success "CUDA Toolkit already installed ($(nvcc --version | grep release | awk '{print $5}' | cut -c2-))"
        else
            sudo apt install -y nvidia-cuda-toolkit
            print_success "CUDA Toolkit installed"
        fi
    fi
else
    print_warning "No NVIDIA GPU detected"
    print_warning "GPU rendering will not be available"
    print_warning "The system will work with CPU rendering only"
fi

#####################################################################
# Install Official Blender with CUDA Support
#####################################################################
print_status "Installing Blender..."

BLENDER_VERSION="5.0.0"
BLENDER_DIR="$HOME/blender-$BLENDER_VERSION-linux-x64"
BLENDER_EXECUTABLE="$BLENDER_DIR/blender"

if [ -f "$BLENDER_EXECUTABLE" ]; then
    print_success "Blender $BLENDER_VERSION already installed at $BLENDER_EXECUTABLE"
else
    print_status "Downloading Blender $BLENDER_VERSION..."

    # Create temporary directory for download
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # Download Blender
    BLENDER_URL="https://mirrors.ocf.berkeley.edu/blender/release/Blender5.0/blender-5.0.0-linux-x64.tar.xz"
    wget -q --show-progress "$BLENDER_URL" -O blender.tar.xz

    print_status "Extracting Blender..."
    tar -xf blender.tar.xz -C "$HOME/"

    # Cleanup
    rm -rf "$TEMP_DIR"
    cd "$PROJECT_DIR"

    print_success "Blender $BLENDER_VERSION installed to $BLENDER_DIR"
fi

# Verify Blender installation
if [ -f "$BLENDER_EXECUTABLE" ]; then
    BLENDER_VER=$("$BLENDER_EXECUTABLE" --version | head -n1)
    print_success "Blender verified: $BLENDER_VER"

    # Test GPU detection if NVIDIA driver is installed
    if command -v nvidia-smi &> /dev/null; then
        print_status "Testing GPU detection in Blender..."
        GPU_TEST=$("$BLENDER_EXECUTABLE" -b --python-expr "import bpy; prefs = bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type = 'CUDA'; prefs.get_devices(); devices = [d.name for d in prefs.devices if d.type == 'CUDA']; print('GPU_DEVICES:', devices)" 2>&1 | grep "GPU_DEVICES:")

        if echo "$GPU_TEST" | grep -q "GPU_DEVICES: \['"; then
            print_success "Blender can detect GPU(s)"
        else
            print_warning "Blender cannot detect GPU - may need official Blender build"
        fi
    fi
else
    print_error "Blender installation failed"
    exit 1
fi

#####################################################################
# Install unrar for RAR archive support
#####################################################################
print_status "Installing unrar..."
sudo apt install -y unrar
print_success "unrar installed"

#####################################################################
# Setup Python Virtual Environment
#####################################################################
cd "$PROJECT_DIR"

print_status "Creating Python virtual environment..."
if [ -d "venv" ]; then
    print_warning "Virtual environment already exists"
    read -p "Recreate virtual environment? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf venv
        python3 -m venv venv
        print_success "Virtual environment recreated"
    fi
else
    python3 -m venv venv
    print_success "Virtual environment created"
fi

# Activate virtual environment and install dependencies
print_status "Installing Python dependencies..."
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install requirements
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
    print_success "Python dependencies installed"
else
    print_error "requirements.txt not found"
    exit 1
fi

#####################################################################
# Create Configuration Files
#####################################################################
print_status "Setting up configuration..."

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        print_success "Created .env from .env.example"
    else
        # Create basic .env file
        cat > .env <<EOF
# Blender Configuration
BLENDER_PATH=$BLENDER_EXECUTABLE
USE_GPU=true
GPU_TYPE=OPTIX

# Flask Configuration
FLASK_ENV=development
SECRET_KEY=$(openssl rand -hex 32)
MAX_CONTENT_LENGTH=52428800000

# Redis Configuration
REDIS_URL=redis://localhost:6379/0
EOF
        print_success "Created .env file"
    fi

    print_warning "Please review and update .env file with your settings"
else
    print_success ".env file already exists"
fi

# Update config.py with Blender path
if [ -f "backend/config.py" ]; then
    print_status "Updating backend/config.py with Blender path..."

    # Backup original config
    cp backend/config.py backend/config.py.backup

    # Update BLENDER_PATH in config.py
    sed -i "s|BLENDER_PATH = .*|BLENDER_PATH = '$BLENDER_EXECUTABLE'|g" backend/config.py

    print_success "Updated config.py with Blender path"
fi

#####################################################################
# Create Required Directories
#####################################################################
print_status "Creating required directories..."

mkdir -p backend/uploads
mkdir -p rendered
mkdir -p logs

# Set permissions
chmod -R 755 backend/uploads rendered logs

print_success "Directories created"

#####################################################################
# Make scripts executable
#####################################################################
print_status "Setting script permissions..."

if [ -f "start_services.sh" ]; then
    chmod +x start_services.sh
fi

if [ -f "stop_services.sh" ]; then
    chmod +x stop_services.sh
fi

print_success "Script permissions set"

#####################################################################
# Test Docker (if user is in docker group)
#####################################################################
print_status "Testing Docker installation..."

# Test if docker works without sudo
if docker ps &> /dev/null; then
    print_success "Docker is working correctly"
else
    print_warning "Docker requires group permissions to take effect"
    print_warning "Please log out and log back in, or run: newgrp docker"
fi

#####################################################################
# Installation Complete
#####################################################################
echo ""
echo -e "${GREEN}======================================"
echo -e "Installation Complete!"
echo -e "======================================${NC}"
echo ""
echo "Installed components:"
echo "  ✓ Python $(python3 --version | awk '{print $2}')"
echo "  ✓ Docker $(docker --version | awk '{print $3}' | tr -d ',')"
echo "  ✓ Docker Compose $(docker compose version | awk '{print $4}')"
if command -v nvidia-smi &> /dev/null; then
    echo "  ✓ NVIDIA Driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)"
fi
if command -v nvcc &> /dev/null; then
    echo "  ✓ CUDA Toolkit $(nvcc --version | grep release | awk '{print $5}' | cut -c2-)"
fi
echo "  ✓ Blender $BLENDER_VERSION at $BLENDER_EXECUTABLE"
echo "  ✓ Python Virtual Environment"
echo "  ✓ All Python dependencies"
echo ""

if ! docker ps &> /dev/null; then
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Log out and log back in (or run: newgrp docker)"
    echo "2. Review and update .env file if needed"
    echo "3. Start services: ./start_services.sh"
else
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review and update .env file if needed"
    echo "2. Start services: ./start_services.sh"
fi

echo ""
echo "Configuration file locations:"
echo "  - Environment: .env"
echo "  - Backend config: backend/config.py"
echo "  - Docker compose: docker-compose.yml"
echo ""

if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${YELLOW}Warning:${NC} No NVIDIA drivers detected"
    echo "GPU rendering will not be available until NVIDIA drivers are installed"
    echo ""
fi

echo -e "${GREEN}Installation script completed successfully!${NC}"
echo ""
