#!/usr/bin/env bash
set -e

# =============================================================================
# build.sh
#
# This script compiles Transmission statically in command-line mode
# for use on a dedicated server
#
# Usage:
# ./build-transmission.sh <VERSION>
# Example:
# ./build-transmission.sh 4.0.6
#
# Notes:
# - Supported versions:
# - 3.00 - oldstable
# - 4.0.6 - stable
# - 4.1.0-beta2 - next
# =============================================================================

# Analyser les arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <VERSION>"
fi

INPUT_VERSION="$1"

# -----------------------------------------------------------------------------
# 0) Global variables
# -----------------------------------------------------------------------------
TRANSMISSION_VERSION="${INPUT_VERSION}"
BUILD="1build1"
FULL_VERSION="${TRANSMISSION_VERSION}-${BUILD}"
CREATE_DEB="true"

case "$TRANSMISSION_VERSION" in
    "4.0.3" | "4.0.4" | "4.0.5")
        TAG="$TRANSMISSION_VERSION"
        STABILITY="oldstable"
        ;;
    "4.0.6")
        TAG="4.0.6"
        STABILITY="stable"
        ;;
    "4.1.0-beta.2" | "4.1.0-beta2")
        TAG="4.1.0-beta.2"
        STABILITY="next"
        ;;
    *)
        echo "ERROR: Unsupported version. Only 4.0.3, 4.0.4, 4.0.5, 4.0.6 and 4.1.0-beta.2 are supported yet."
        exit 1
        ;;
esac

echo "====> Building Transmission $TRANSMISSION_VERSION (build: $BUILD)"
echo "====> Full version: $FULL_VERSION"
echo "====> Build mode: CLI only (server mode)"
echo "====> Stability: $STABILITY"
WHEREAMI="$(dirname "$(readlink -f "$0")")"
PREFIX="/usr"
BASE_DIR="$PWD/custom_build"
mkdir -p "$BASE_DIR"
INSTALL_DIR="$BASE_DIR/install"
mkdir -p "$INSTALL_DIR"
ARCHITECTURE=$(dpkg --print-architecture)
CORES=$(nproc)


# -----------------------------------------------------------------------------
# 1) Download and build Transmission
# -----------------------------------------------------------------------------
build_transmission() {
    echo "====> Downloading and building Transmission $TRANSMISSION_VERSION"
    sudo apt install libnatpmp-dev libminiupnpc-dev
    local SRC_DIR="$BASE_DIR/transmission-$TRANSMISSION_VERSION"
    echo "====> Cleaning any existing Transmission directories"
    cd "$BASE_DIR"
    rm -rf transmission-*
    echo "====> Downloading Transmission"
    git clone --depth 1 --recursive --recurse-submodules --branch "$TAG" "https://github.com/transmission/transmission.git" "$SRC_DIR"
    cd "$SRC_DIR"
    git --no-pager log -1 --oneline
    mkdir -p build
    cd build
    echo "====> Configuring Transmission with CMake (static build)"
    export CFLAGS="-O3 -fPIC"
    export CXXFLAGS="-O3 -fPIC"
    local CMAKE_OPTS=""  
    CMAKE_OPTS="-DENABLE_GTK=OFF \
                -DENABLE_CLI=ON \
                -DENABLE_UTILS=ON \
                -DENABLE_DAEMON=ON \
                -DINSTALL_WEB=ON \
                -DENABLE_NLS=ON \
                -DINSTALL_LIB=ON \
                -DENABLE_QT=OFF \
                -DENABLE_MAC=OFF \
                -DENABLE_TESTS=OFF \
                -DUSE_SYSTEM_MINIUPNPC=ON \
                -DUSE_SYSTEM_NATPMP=ON"
    
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$PREFIX \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        $CMAKE_OPTS
    echo "====> Building Transmission"
    make -j"$CORES"
    echo "====> Installing Transmission to $INSTALL_DIR"
    make DESTDIR="$INSTALL_DIR" install
    cd "$WHEREAMI"
}

# -----------------------------------------------------------------------------
# 2) Create the Transmission package
# -----------------------------------------------------------------------------
create_package() {
    echo "====> Creating Transmission package"
    if [ ! -f "$INSTALL_DIR$PREFIX/bin/transmission-cli" ]; then
        echo "ERROR: Transmission binaries not found at $INSTALL_DIR$PREFIX/bin/transmission-cli"
        echo "Compilation might have failed."
        exit 1
    fi
    echo "====> Transmission binaries information:"
    file "$INSTALL_DIR$PREFIX/bin/transmission-cli"
    echo "====> Copying Transmission binaries to output directory"
    mkdir -p "$WHEREAMI/output"
    local EXECUTABLES=("transmission-cli" "transmission-create" "transmission-edit" "transmission-remote" "transmission-show" "transmission-daemon")
    for executable in "${EXECUTABLES[@]}"; do
        if [ -f "$INSTALL_DIR$PREFIX/bin/$executable" ]; then
            cp "$INSTALL_DIR$PREFIX/bin/$executable" "$WHEREAMI/output/"
            chmod +x "$WHEREAMI/output/$executable"
            echo "====> Copied $executable to output directory"
        else
            echo "WARN: $executable not found, skipping"
        fi
    done
    
    if [ -n "$CREATE_DEB" ] && [ "$CREATE_DEB" = "true" ]; then
        echo "====> Creating Debian package"
        local PKG_DIR os_name codename os PACKAGE_NAME INSTALL_PATH INSTALLED_SIZE
        PKG_DIR="$BASE_DIR/deb-pkg"
        os_name=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
        codename=$(lsb_release -cs)
        os="${os_name}-${codename}"
        PACKAGE_NAME="transmission-${STABILITY}_${TRANSMISSION_VERSION}-${BUILD}_${os}_${ARCHITECTURE}.deb"
        rm -rf "$PKG_DIR"
        mkdir -p "$PKG_DIR/DEBIAN"
        INSTALL_PATH="/opt/MediaEase/.binaries/installed/transmission-${STABILITY}_${TRANSMISSION_VERSION}"
        mkdir -p "$PKG_DIR/$INSTALL_PATH"
        cp -r "$INSTALL_DIR$PREFIX" "$PKG_DIR/$INSTALL_PATH/"
        find "$PKG_DIR" -type f -executable -exec file {} \; \
            | grep "ELF.*executable" \
            | cut -d: -f1 \
            | xargs --no-run-if-empty -I{} sh -c 'echo "Processing: {}" && strip --strip-unneeded "{}" && echo "  ✓ Stripped" && if command -v upx >/dev/null 2>&1; then upx --best --lzma "{}" && echo "  ✓ Compressed with UPX"; else echo "  ℹ UPX not available"; fi' || echo "Warning: Some files could not be processed"
        INSTALLED_SIZE="$(du -sk "$PKG_DIR/opt" | cut -f1)"
        cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: transmission-${STABILITY}
Version: ${TRANSMISSION_VERSION}-${BUILD}
Architecture: ${ARCHITECTURE}
Maintainer: ${COMMITTER_NAME} <${COMMITTER_EMAIL}>
Installed-Size: ${INSTALLED_SIZE}
Depends: libssl3, libcurl4, libsystemd0, libminiupnpc17 | libminiupnpc10, libnatpmp1, libc6, zlib1g, libminiupnpc-dev, libnatpmp-dev
Conflicts: transmission-daemon, transmission-cli, transmission-common, transmission-remote-gtk, transmission-qt, transmission-gtk, libtransmission-client-perl
Section: net
Priority: optional
Homepage: https://transmissionbt.com/
Description: BitTorrent client (CLI tools, daemon mode)
 Transmission BitTorrent client compiled statically for server usage.
 Contains CLI tools and daemon with WebUI.
 .
 This package contains:
  * CLI tools: transmission-cli, transmission-create, transmission-edit,
    transmission-show, transmission-remote
  * Daemon mode: transmission-daemon with WebUI
 .
 Compiled on $(date +%Y-%m-%d)
EOF
        cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e
case "$1" in
    configure)
        PKG_NAME="${DPKG_MAINTSCRIPT_PACKAGE}"
        PKG_VERSION="$(dpkg-query -W -f='${Version}' "${PKG_NAME}")"
        BASE_VERSION="${PKG_VERSION%-*}"
        INSTALL_BASE="/opt/MediaEase/.binaries/installed/${PKG_NAME}_${BASE_VERSION}"
        INSTALL_USR="${INSTALL_BASE}/usr"
        ENV_FILE="${INSTALL_BASE}/.env"

        case "${PKG_NAME}" in
        *-next)
            PRIORITY=60
            ;;
        *-oldstable)
            PRIORITY=40
            ;;
        *-stable)
            PRIORITY=50
            ;;
        *)
            PRIORITY=40
            ;;
        esac
        
        cat > "${ENV_FILE}" <<EOF2
export PATH="${INSTALL_USR}/bin:\$PATH"
export TRANSMISSION_WEB_HOME="${INSTALL_USR}/share/transmission/web"
EOF2
        for bin in transmission-cli transmission-create transmission-edit transmission-remote transmission-show transmission-daemon; do
            if [ -f "${INSTALL_USR}/bin/${bin}" ]; then
                update-alternatives --install "/usr/bin/${bin}" "${bin}" "${INSTALL_USR}/bin/${bin}" ${PRIORITY}
            fi
        done
        if [ -d "${INSTALL_USR}/share/transmission/web" ]; then
            update-alternatives --install "/usr/share/transmission/web" "transmission-web" "${INSTALL_USR}/share/transmission/web" ${PRIORITY}
        fi
        if command -v mandb >/dev/null 2>&1; then
            mandb || true
        fi
    ;;
    abort-upgrade|abort-install|abort-remove)
    ;;
    *)
    ;;
esac

exit 0
EOF
        cat > "$PKG_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/sh
set -e
case "$1" in
    remove|deconfigure)
        PKG_NAME="${DPKG_MAINTSCRIPT_PACKAGE:-transmission-stable}"
        PKG_VERSION="$(dpkg-query -W -f='${Version}' "${PKG_NAME}")"
        BASE_VERSION="${PKG_VERSION%-*}"
        INSTALL_BASE="/opt/MediaEase/.binaries/installed/${PKG_NAME}_${BASE_VERSION}"
        INSTALL_USR="${INSTALL_BASE}/usr"
        for bin in transmission-cli transmission-create transmission-edit transmission-remote transmission-show transmission-daemon; do
            if [ -f "${INSTALL_USR}/bin/${bin}" ]; then
                update-alternatives --remove "${bin}" "${INSTALL_USR}/bin/${bin}" || true
            fi
        done
        if [ -d "${INSTALL_USR}/share/transmission/web" ]; then
            update-alternatives --remove "transmission-web" "${INSTALL_USR}/share/transmission/web" || true
        fi
    ;;
    upgrade|failed-upgrade|abort-install|abort-upgrade|disappear)
    ;;
    *)
        echo "prerm called with an unknown argument \`$1\`" >&2
        exit 1
    ;;
esac
exit 0
EOF
        echo "Generating md5sums..."
        (
            cd "$PKG_DIR"
            find . -type f ! -path "./DEBIAN/*" -exec md5sum {} \; > DEBIAN/md5sums
        )
        chmod 755 "$PKG_DIR/DEBIAN/postinst" "$PKG_DIR/DEBIAN/prerm"
        cd "$WHEREAMI"
        dpkg-deb --build -Zxz -z9 -Sextreme --root-owner-group "$PKG_DIR" "output/$PACKAGE_NAME"
        
        echo "====> Debian package created at:"
        echo "$WHEREAMI/output/$PACKAGE_NAME"
    fi
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------
build_transmission
create_package

echo "====> All done! Transmission $TRANSMISSION_VERSION has been built."
echo "====> The binaries are at $WHEREAMI/output/"
if [ -n "$CREATE_DEB" ] && [ "$CREATE_DEB" = "true" ]; then
    echo "====> The Debian package is at $WHEREAMI/output/transmission-${STABILITY}_${TRANSMISSION_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
fi
exit 0 
