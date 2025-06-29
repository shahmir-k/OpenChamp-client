#!/bin/bash

# OpenChamp Client Installation Script for Linux
# Shahmir Khan - Saturday 28th June 2025
# https://github.com/shahmir-khan

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default Godot version
DEFAULT_GODOT_VERSION="4.4.1"
GODOT_VERSION=${1:-$DEFAULT_GODOT_VERSION}
LAUNCH_PROJECT=${2:-true}  # Changed default to true for better UX
AUTO_CLONE=${3:-false}     # Auto-clone repository if not found

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to download Godot
download_godot() {
    local version=$1
    local godot_dir="godot-${version}"
    
    print_status "Downloading Godot Engine version ${version}..."
    
    # Create godot directory if it doesn't exist
    mkdir -p "$godot_dir"
    
    # Correct URL format based on official Godot releases
    local download_url="https://github.com/godotengine/godot/releases/download/${version}-stable/Godot_v${version}-stable_linux.x86_64.zip"
    local zip_file="${godot_dir}/godot.zip"
    
    print_status "Downloading from: $download_url"
    
    if curl -L -o "$zip_file" "$download_url"; then
        # Check if download was successful (file size > 1MB)
        if [ -s "$zip_file" ] && [ $(stat -c%s "$zip_file") -gt 1048576 ]; then
            print_success "Download completed!"
            
            # Extract the zip file
            print_status "Extracting Godot..."
            cd "$godot_dir"
            
            if unzip -q "godot.zip"; then
                rm "godot.zip"
                
                # Make the Godot binary executable
                chmod +x "Godot_v${version}-stable_linux.x86_64"
                
                # Create a symlink for easier access
                ln -sf "Godot_v${version}-stable_linux.x86_64" "godot"
                
                cd ..
                print_success "Godot Engine ${version} installed successfully!"
                return 0
            else
                print_error "Failed to extract Godot zip file"
                cd ..
                return 1
            fi
        else
            print_error "Download failed - file is too small or empty"
            rm -f "$zip_file"
            return 1
        fi
    else
        print_error "Failed to download Godot Engine ${version}"
        return 1
    fi
}

# Function to check if Godot is already installed
check_godot_installed() {
    local version=$1
    local godot_dir="godot-${version}"
    
    if [ -d "$godot_dir" ] && [ -f "$godot_dir/godot" ]; then
        return 0
    else
        return 1
    fi
}

# Function to launch project with Godot
launch_project() {
    local version=$1
    local godot_dir="godot-${version}"
    local godot_bin="$godot_dir/godot"
    
    if [ -f "$godot_bin" ]; then
        print_status "Launching project with Godot ${version}..."
        "$godot_bin" --path . &
        print_success "Project launched!"
    else
        print_error "Godot binary not found at $godot_bin"
        return 1
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [GODOT_VERSION] [LAUNCH] [AUTO_CLONE]"
    echo ""
    echo "Arguments:"
    echo "  GODOT_VERSION    Godot version to download (default: $DEFAULT_GODOT_VERSION)"
    echo "  LAUNCH           Set to 'true' to launch project after installation"
    echo "  AUTO_CLONE       Set to 'true' to auto-clone repository if not found"
    echo ""
    echo "Examples:"
    echo "  $0                    # Install with default version ($DEFAULT_GODOT_VERSION)"
    echo "  $0 4.3.3             # Install Godot 4.3.3"
    echo "  $0 4.3.3 true        # Install Godot 4.3.3 and launch project"
    echo "  $0 4.4.0 true        # Install Godot 4.4.0 and launch project"
}

# Check if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Check if we're in the right directory or need to download the project
if [ ! -f "install.py" ]; then
    # Check if we're in a parent directory that might contain the project
    if [ -f "client-4.4_main/install.py" ]; then
        print_status "Found project in client-4.4_main directory, changing to it..."
        cd client-4.4_main
    elif [ -f "client/install.py" ]; then
        print_status "Found project in client directory, changing to it..."
        cd client
    else
        if [ "$AUTO_CLONE" = "true" ]; then
            print_status "Auto-cloning OpenChamp client repository..."
            git clone https://github.com/OpenChamp/client.git
            cd client
            print_success "Repository cloned successfully!"
        else
            print_error "OpenChamp client project not found in current directory"
            print_error "Please either:"
            print_error "1. Run this script from the client-4.4_main directory, or"
            print_error "2. Clone the repository first: git clone https://github.com/OpenChamp/client.git, or"
            print_error "3. Use auto-clone: $0 $GODOT_VERSION $LAUNCH_PROJECT true"
            exit 1
        fi
    fi
fi

print_status "Starting OpenChamp Client installation with Godot ${GODOT_VERSION}..."

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d'.' -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d'.' -f2)

print_status "Detected Python version: $PYTHON_VERSION"

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 12 ]); then
    print_error "Python 3.12 or higher is required. Found: $PYTHON_VERSION"
    print_error "Please update Python and try again"
    exit 1
fi

# Check if virtual environment already exists
if [ -d "venv" ]; then
    print_warning "Virtual environment already exists. Using existing one."
else
    print_status "Creating virtual environment..."
    python3 -m venv venv
    print_success "Virtual environment created successfully!"
fi

# Activate the virtual environment
print_status "Activating virtual environment..."
source venv/bin/activate

# Check if requests is already installed
if python -c "import requests" 2>/dev/null; then
    print_warning "Requests library already installed. Skipping installation."
else
    print_status "Installing requests library..."
    pip install requests
    print_success "Requests library installed successfully!"
fi

# Clone godot-cpp submodule if it doesn't exist
if [ ! -d "extensions/godot-cpp/.git" ]; then
    print_status "Cloning godot-cpp submodule..."
    cd extensions
    git clone https://github.com/godotengine/godot-cpp.git
    cd godot-cpp
    git checkout 4.3
    cd ../..
    print_success "godot-cpp submodule cloned successfully!"
else
    print_warning "godot-cpp submodule already exists."
fi

# Clone default_assets submodule if it doesn't exist
if [ ! -d "default_assets/.git" ]; then
    print_status "Cloning default_assets repository..."
    git clone https://github.com/OpenChamp/default_assets.git
    print_success "default_assets repository cloned successfully!"
else
    print_warning "default_assets repository already exists."
fi

# Generate manifests for default_assets
if [ -f "default_assets/manifests.py" ]; then
    print_status "Generating manifests for default_assets..."
    cd default_assets
    python3 manifests.py
    cd ..
    print_success "Manifests generated successfully!"
fi

# Initialize git repository if not already a git repo
if [ ! -d ".git" ]; then
    print_status "Initializing git repository..."
    git init
    git remote add origin https://github.com/OpenChamp/client.git
    print_success "Git repository initialized!"
fi

# Try to fetch and reset to the correct branch if we have a remote
if git remote get-url origin >/dev/null 2>&1; then
    print_status "Fetching latest changes from remote..."
    git fetch origin
    if git show-ref --verify --quiet refs/remotes/origin/4.4_main; then
        print_status "Resetting to 4.4_main branch..."
        git reset --hard origin/4.4_main
        print_success "Repository updated to 4.4_main branch!"
    else
        print_warning "Could not find 4.4_main branch, continuing with current state..."
    fi
fi

# Run the install script
print_status "Running main installation script..."
python3 install.py

# Download and setup Godot
if check_godot_installed "$GODOT_VERSION"; then
    print_warning "Godot ${GODOT_VERSION} already installed. Skipping download."
else
    download_godot "$GODOT_VERSION"
fi

print_success "Installation completed successfully!"

# Launch project if requested
if [ "$LAUNCH_PROJECT" = "true" ]; then
    launch_project "$GODOT_VERSION"
elif [ "$LAUNCH_PROJECT" = "interactive" ]; then
    echo -e "${BLUE}[PROMPT]${NC} Do you want to launch the project now? (y/n): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        launch_project "$GODOT_VERSION"
    fi
fi

print_status "You can now open the project in Godot Engine by importing project.godot"
print_status "Or run: ./godot-${GODOT_VERSION}/godot --path ."
print_status "Virtual environment is active. Use 'deactivate' to exit it when done."