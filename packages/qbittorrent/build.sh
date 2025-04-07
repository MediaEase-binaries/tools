#!/usr/bin/env bash
set -e

# =============================================================================
# build.sh
#
# This script handles the building of qBittorrent components (nox and cli).
#
# It performs:
# - Download and compilation of qBittorrent
# - Live installation in the /opt/MediaEase/.binaries/installed/... prefix
# - Staging installation via DESTDIR for final packaging
#
# The final package will contain all components and include:
# - A generated md5sums file
#
# Usage:
# ./build.sh <VERSION>
# Example:
# ./build.sh 4.6.7 or 5.0.3 or 5.1.0
#
# Notes:
# - All configures use the following prefix:
# /opt/MediaEase/.binaries/installed/qbittorrent_${QBITTORRENT_VER}
# =============================================================================

usage() {
    echo "Usage: $0 <VERSION>"
    echo "Example: $0 4.6.7"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

# -----------------------------------------------------------------------------
# 0) Parameter analysis and definition of global variables
# -----------------------------------------------------------------------------
INPUT_VERSION="$1"                           # Ex: "4.6.7"
REAL_VERSION="${INPUT_VERSION%%-*}"          # Ex: "4.6.7"
BUILD="1build1"                              # Build version
FULL_VERSION="${REAL_VERSION}-${BUILD}"      # Ex: "4.6.7-1build1"

echo "====> Building qBittorrent $REAL_VERSION (build: $BUILD)"
echo "====> Full version: $FULL_VERSION"

QBITTORRENT_VER="$INPUT_VERSION"

# Get the absolute path to the tools directory
WHEREAMI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR_PACKAGE="$WHEREAMI/packages/qbittorrent"
ARCHITECTURE="amd64"
BASE_DIR="$PWD/custom_build"
mkdir -p "$BASE_DIR"
INSTALL_DIR="$BASE_DIR/install"
mkdir -p "$INSTALL_DIR"

codename=$(lsb_release -cs)
distro=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
os=$distro-$codename
export os

# -----------------------------------------------------------------------------
# 1) Extract dependency versions
# -----------------------------------------------------------------------------
extract_dependency_versions() {
    echo "====> Extracting dependency versions"
    
    # Extract Qt version
    QT_VERSION=$(dpkg-query -W -f='${Version}' qt6 | cut -d'-' -f1)
    echo "====> Found Qt version: $QT_VERSION"
    
    # Extract libtorrent version
    LIBTORRENT_VERSION=$(dpkg-query -W -f='${Version}' libtorrent-rasterbar | cut -d'-' -f1)
    echo "====> Found libtorrent version: $LIBTORRENT_VERSION"
    
    # Extract Boost version
    BOOST_VERSION=$(dpkg-query -W -f='${Version}' libboost-all-dev | cut -d'-' -f1)
    echo "====> Found Boost version: $BOOST_VERSION"
    export BOOST_VERSION QT_VERSION LIBTORRENT_VERSION

    OPENSSL_VERSION=$(dpkg-query -W -f='${Version}' libssl-dev | cut -d'-' -f1)
    echo "====> Found OpenSSL version: $OPENSSL_VERSION"
    export OPENSSL_VERSION
}

# -----------------------------------------------------------------------------
# 2) qBittorrent build
# -----------------------------------------------------------------------------
build_qbittorrent() {
    echo "====> Building qBittorrent"
    local GIT_REPO_URL SRC_DIR TMP_DIR
    TMP_DIR=$(mktemp -d)
    GIT_REPO_URL="https://github.com/qbittorrent/qBittorrent/archive/release-${QBITTORRENT_VER}.tar.gz"
    SRC_DIR="$BASE_DIR/qBittorrent-release-$QBITTORRENT_VER"
    rm -rf "$SRC_DIR"
    
    echo "====> Downloading qBittorrent"
    echo "====> GIT_REPO_URL: $GIT_REPO_URL"
    curl -NL "$GIT_REPO_URL" -o qbittorrent.tar.gz
    tar xf qbittorrent.tar.gz -C "$BASE_DIR"
    cd "$SRC_DIR"
    QT6_MODULE_DIR=$(dirname "$(find /usr -type f -name 'FindQt6.cmake' | head -n1)")
    QT6_CONFIG_DIR=$(dirname "$(find /usr -type f -name 'Qt6Config.cmake' | head -n1)")
    TARGET_FILES=$(find / -type f -name 'LibtorrentRasterbarTargets.cmake')
    for file in $TARGET_FILES; do
        sudo sed -i \
            -e 's|/__w/rasterbar-builds/rasterbar-builds/libtorrent/include|/usr/include|g' \
            -e 's|/__w/rasterbar-builds/rasterbar-builds/libtorrent/lib|/usr/lib/x86_64-linux-gnu|g' \
            -e 's|/__w/rasterbar-builds/rasterbar-builds/libtorrent/build|/usr/lib/x86_64-linux-gnu|g' \
            "$file"
    done
    OPENSSL_CRYPTO_LIBRARY=$(find /usr/ -type f -name 'libcrypto.so' | head -n1)
    OPENSSL_SSL_LIBRARY=$(find /usr/ -type f -name 'libssl.so' | head -n1)
    stdcver="c++17"
    if [[ "$QBITTORRENT_VER" == 5.* ]]; then
        stdcver="c++20"
    fi
    # Configure and build using cmake
    echo "====> Generating toolchain file"
    cmake_toolchain_file="$TMP_DIR/toolchain.cmake"
    cat > "$cmake_toolchain_file" << EOL
set(CMAKE_BUILD_TYPE "release")
set(CMAKE_CXX_STANDARD ${stdcver//[^0-9]/})
set(CMAKE_CXX_FLAGS "-O3 -march=native")
set(CMAKE_INSTALL_PREFIX /usr)
set(CMAKE_MODULE_PATH ${QT6_MODULE_DIR})
set(Qt6_DIR ${QT6_CONFIG_DIR})
set(QT6 OFF)
set(Boost_NO_BOOST_CMAKE TRUE)
set(OPENSSL_INCLUDE_DIR /usr/include)
set(OPENSSL_CRYPTO_LIBRARY ${OPENSSL_CRYPTO_LIBRARY})
set(OPENSSL_SSL_LIBRARY ${OPENSSL_SSL_LIBRARY})
set(GUI OFF)
set(DBUS ON)
set(SYSTEMD ON)
EOL

    # Use the toolchain file
    cmake -Wno-dev -G Ninja -B build \
        -DCMAKE_TOOLCHAIN_FILE="$cmake_toolchain_file"

    cmake --build build --parallel $(nproc)
    DESTDIR="$TMP_DIR" cmake --install build

    # Copy files to install directory
    cp -pR "$TMP_DIR/"* "$INSTALL_DIR/"
    
    # Optimize binaries
    echo "====> Optimizing qBittorrent binaries"
    find "$INSTALL_DIR" -type f -exec file {} \; | grep ELF | cut -d: -f1 | while read -r file; do
        if [ -f "$file" ] && [ -x "$file" ]; then
            strip --strip-unneeded "$file" 2>/dev/null || true
            if file "$file" | grep -q "ELF.*executable" && command -v upx >/dev/null 2>&1; then
                upx --best --lzma "$file" 2>/dev/null || true
            fi
        fi
    done

    cd "$WHEREAMI"
    rm -rf "$TMP_DIR" qbittorrent.tar.gz
}

# -----------------------------------------------------------------------------
# 3) Final packaging
# -----------------------------------------------------------------------------
package_qbittorrent_deb() {
    echo "====> Packaging qBittorrent to .deb file"
    local PKG_DIR
    PKG_DIR="$BASE_DIR/pkg_qbittorrent"
    DEB_DIR="$PKG_DIR/DEBIAN"
    rm -rf "$PKG_DIR"
    mkdir -p "$DEB_DIR"
    mkdir -p "$PKG_DIR/usr"
    rsync -a "$INSTALL_DIR/" "$PKG_DIR/"

    if [ -z "$(ls -A "$PKG_DIR/usr")" ]; then
        echo "ERROR: $PKG_DIR/usr is empty."
        exit 1
    fi

    echo "====> Copying control file"
    cp -pr "$TOOLS_DIR_PACKAGE/control" "$DEB_DIR/control"

    echo "====> Setting control file values"
    sed -i \
        -e "s|@REVISION@|1build1|g" \
        -e "s|@ARCHITECTURE@|${ARCHITECTURE}|g" \
        -e "s|@VERSION@|${REAL_VERSION}|g" \
        -e "s|@DATE@|$(date +%Y-%m-%d)|g" \
        -e "s|@SIZE@|$(du -s -k "$PKG_DIR/usr" | cut -f1)|g" \
        -e "s|@QT_VERSION@|${QT_VERSION}|g" \
        -e "s|@LIBTORRENT_VERSION@|${LIBTORRENT_VERSION}|g" \
        -e "s|@BOOST_VERSION@|${BOOST_VERSION}|g" \
        "$DEB_DIR/control"

    echo "====> Generating md5sums"
    find "$PKG_DIR" -type f ! -path './DEBIAN/*' -exec md5sum {} \; > "$DEB_DIR/md5sums"

    package_name="qbittorrent-nox-${STABILITY}_${REAL_VERSION}-1build1_${os}_${ARCHITECTURE}.deb"
    cd "$WHEREAMI"
    dpkg-deb --build -Zxz -z9 -Sextreme --root-owner-group "$PKG_DIR" "${package_name}"
    
    package_location=$(find "$WHEREAMI" -name "$package_name")
    if [ -f "$package_location" ]; then
        echo "Package created at: $package_location"
    else
        echo "ERROR: Package not found."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Sequential execution of builds
# -----------------------------------------------------------------------------
extract_dependency_versions
build_qbittorrent
package_qbittorrent_deb

echo "====> qBittorrent $FULL_VERSION has been built and packaged successfully."
