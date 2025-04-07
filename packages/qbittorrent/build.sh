#!/bin/bash
set -e

# Check if version is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

QBITTORRENT_VERSION="$1"
REPO_URL="https://github.com/qbittorrent/qBittorrent.git"
TEMP_DIR="/tmp/qbittorrent-build"
INSTALL_DIR="${TEMP_DIR}/install"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Determine stability based on version
if [[ "$QBITTORRENT_VERSION" == "4.6.7" ]]; then
    TAG="release-4.6.7"
elif [[ "$QBITTORRENT_VERSION" == "5.0.0" ]]; then
    TAG="release-5.0.0"
elif [[ "$QBITTORRENT_VERSION" == "5.1.0rc1" ]]; then
    TAG="release-5.1.0rc1"
else
    echo "Unsupported qBittorrent version: ${QBITTORRENT_VERSION}"
    exit 1
fi

# Function to install build dependencies
install_dependencies() {
    apt-get update
    apt-get install -y \
        build-essential \
        cmake \
        git \
        ninja-build \
        pkg-config \
        libboost-dev \
        libssl-dev \
        zlib1g-dev \
        libgl1-mesa-dev \
        python3 \
        libtorrent-rasterbar-dev
}

# Function to clone and checkout the repository
clone_repository() {
    mkdir -p "${TEMP_DIR}"
    cd "${TEMP_DIR}"
    
    if [ -d "qBittorrent" ]; then
        cd qBittorrent
        git fetch --all
        git reset --hard
    else
        git clone "${REPO_URL}" qBittorrent
        cd qBittorrent
    fi
    
    git checkout "${TAG}"
}

# Function to build qBittorrent
build_qbittorrent() {
    cd "${TEMP_DIR}/qBittorrent"
    cmake -G "Ninja" -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" -DGUI=OFF
    cmake --build build
    cmake --install build
}

# Main execution
main() {
    install_dependencies
    clone_repository
    build_qbittorrent
}

# Execute main function
main
