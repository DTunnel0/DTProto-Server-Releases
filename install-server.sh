#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
GITHUB_REPO="DTunnel0/DTProto-Server-Releases"
BINARY_NAME="proto-server"
MANAGER_SCRIPT="proto-server.sh"
INSTALL_DIR="/usr/local/bin"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

detect_architecture() {
    local arch=$(uname -m)
    local os="linux"
    
    case $arch in
        x86_64)
            echo "${os}-amd64"
            ;;
        aarch64|arm64)
            echo "${os}-arm64"
            ;;
        armv7l|armv6l)
            echo "${os}-arm"
            ;;
        i386|i686)
            echo "${os}-386"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

get_latest_version() {
    local version=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')
    
    if [ -z "$version" ]; then
        print_error "Failed to fetch latest version" >&2
        exit 1
    fi
    
    echo "$version"
}

download_binary() {
    local version=$1
    local arch=$2
    local binary_name="${BINARY_NAME}-${arch}"
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/${binary_name}"
    
    print_info "Downloading ${binary_name}..."
    
    if ! curl -L -o "/tmp/${binary_name}" "${download_url}"; then
        print_error "Failed to download binary"
        exit 1
    fi
    
    chmod +x "/tmp/${binary_name}"
    print_success "Binary downloaded successfully"
}

install_binary() {
    local arch=$1
    local binary_name="${BINARY_NAME}-${arch}"
    
    print_info "Installing binary to ${INSTALL_DIR}/${BINARY_NAME}..."
    
    if [ "$EUID" -eq 0 ]; then
        mv "/tmp/${binary_name}" "${INSTALL_DIR}/${BINARY_NAME}"
        chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    else
        sudo mv "/tmp/${binary_name}" "${INSTALL_DIR}/${BINARY_NAME}"
        sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    fi
    
    print_success "Binary installed to ${INSTALL_DIR}/${BINARY_NAME}"
}

download_manager_script() {
    local download_url="https://raw.githubusercontent.com/${GITHUB_REPO}/main/${MANAGER_SCRIPT}"
    
    print_info "Downloading management script..."
    
    if curl -L -o "/tmp/${MANAGER_SCRIPT}" "${download_url}" 2>/dev/null; then
        if [ "$EUID" -eq 0 ]; then
            mv "/tmp/${MANAGER_SCRIPT}" "${INSTALL_DIR}/proto"
            chmod +x "${INSTALL_DIR}/proto"
        else
            sudo mv "/tmp/${MANAGER_SCRIPT}" "${INSTALL_DIR}/proto"
            sudo chmod +x "${INSTALL_DIR}/proto"
        fi
        print_success "Management script installed as: proto"
    else
        print_info "Management script not found, skipping..."
    fi
}

main() {
    echo ""
    echo "=========================================="
    echo "   Proto Server Installation Script"
    echo "=========================================="
    echo ""
    
    ARCH=$(detect_architecture)
    print_info "Detected architecture: ${ARCH}"
    
    print_info "Fetching latest version..."
    VERSION=$(get_latest_version)
    print_info "Latest version: ${VERSION}"
    
    download_binary "$VERSION" "$ARCH"
    install_binary "$ARCH"
    download_manager_script
    
    echo ""
    echo "=========================================="
    print_success "Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Binary installed at: ${INSTALL_DIR}/${BINARY_NAME}"
    echo "Manager installed at: ${INSTALL_DIR}/proto"
    echo ""
    echo "Run the management tool with:"
    echo "  proto"
    echo ""
    echo "Or run directly with:"
    echo "  proto-server --token YOUR_TOKEN"
    echo ""
}

main "$@"
