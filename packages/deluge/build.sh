#!/usr/bin/env bash
set -e

# =============================================================================
# build.sh
#
# This script compiles Deluge statically in command-line mode
# for use on a dedicated server
#
# Usage:
# ./build.sh <VERSION>
# Example:
# ./build.sh 2.1.1
#
# Notes:
# - Supported versions:
# - 2.0.5 - oldstable
# - 2.1.1 - stable
# - 2.2.0 - next (development version)
# =============================================================================

usage() {
    echo "Usage: $0 <VERSION>"
    echo "Example: $0 2.1.1"
    echo "Supported versions: 2.0.5, 2.1.1, 2.2.0"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi
INPUT_VERSION="$1"

# -----------------------------------------------------------------------------
# 0) Parameters and global variables
# -----------------------------------------------------------------------------
DELUGE_VERSION="${INPUT_VERSION}"
BUILD="1build1"
FULL_VERSION="${DELUGE_VERSION}-${BUILD}"
CREATE_DEB="true"
case "$DELUGE_VERSION" in
    "2.0.5")
        TAG="deluge-2.0.5"
        STABILITY="oldstable"
        LIBTORRENT_VERSION="2.0.5"
        ;;
    "2.1.1")
        TAG="deluge-2.1.1"
        STABILITY="stable"
        LIBTORRENT_VERSION="2.0.8"
        ;;
    "2.2.0")
        TAG="develop"
        STABILITY="next"
        LIBTORRENT_VERSION="2.0.11"
        ;;
    *)
        echo "ERROR: Unsupported version. Supported versions are: 2.0.5, 2.1.1, 2.2.0"
        exit 1
        ;;
esac

echo "====> Building Deluge $DELUGE_VERSION (build: $BUILD)"
echo "====> Full version: $FULL_VERSION"
echo "====> Build mode: CLI/Web only (server mode)"
echo "====> Stability: $STABILITY"
echo "====> Using libtorrent: $LIBTORRENT_VERSION"
WHEREAMI="$(dirname "$(readlink -f "$0")")"
PREFIX="/usr"
BASE_DIR="$PWD/custom_build"
mkdir -p "$BASE_DIR"
INSTALL_DIR="$BASE_DIR/install"
mkdir -p "$INSTALL_DIR"
ARCHITECTURE=$(dpkg --print-architecture)
CORES=$(nproc)
PYTHON_VERSION="3"
PYTHON_CMD="python3"

# -----------------------------------------------------------------------------
# 1) Install required dependencies
# -----------------------------------------------------------------------------
install_dependencies() {
    echo "====> Installing required dependencies"
    sudo apt-get update
    sudo apt-get install -y build-essential cmake pkg-config libssl-dev \
                        zlib1g-dev libgeoip-dev ${PYTHON_CMD} \
                        ${PYTHON_CMD}-dev ${PYTHON_CMD}-pip \
                        ${PYTHON_CMD}-setuptools ${PYTHON_CMD}-wheel
    ${PYTHON_CMD} -m pip install --upgrade pip
    ${PYTHON_CMD} -m pip install twisted pyopenssl service_identity pillow \
                        rencode pyxdg chardet setproctitle setuptools wheel
}

# -----------------------------------------------------------------------------
# 2) Install libtorrent-rasterbar
# -----------------------------------------------------------------------------
install_libtorrent() {
    echo "====> Installing libtorrent-rasterbar $LIBTORRENT_VERSION from MediaEase repository"
    local LIBTORRENT_PACKAGE_NAME="libtorrent-rasterbar-mediaease_${LIBTORRENT_VERSION}-1build1_amd64.deb"
    if dpkg -l | grep -q "libtorrent-rasterbar-mediaease" && dpkg -l | grep "libtorrent-rasterbar-mediaease" | grep -q "$LIBTORRENT_VERSION"; then
        echo "====> libtorrent-rasterbar-mediaease $LIBTORRENT_VERSION is already installed"
    else
        echo "====> Installing libtorrent-rasterbar-mediaease $LIBTORRENT_VERSION from tools directory"
        local LIBTORRENT_PACKAGE="$WHEREAMI/tools/$LIBTORRENT_PACKAGE_NAME"
        if [ ! -f "$LIBTORRENT_PACKAGE" ]; then
            echo "ERROR: $LIBTORRENT_PACKAGE_NAME not found in the tools directory!"
            echo "Please download the libtorrent-rasterbar-mediaease package and place it in the tools directory."
            exit 1
        fi
        echo "====> Found libtorrent package: $LIBTORRENT_PACKAGE"
        sudo dpkg -i "$LIBTORRENT_PACKAGE"
    fi
    if ! pkg-config --exists libtorrent-rasterbar; then
        echo "ERROR: libtorrent-rasterbar not found with pkg-config!"
        echo "The libtorrent package might not be installed correctly or pkg-config files are missing."
        exit 1
    fi
    echo "====> Installing Python bindings for libtorrent-rasterbar"
    ${PYTHON_CMD} -m pip install --upgrade python-libtorrent
    echo "====> libtorrent-rasterbar configuration completed"
}

# -----------------------------------------------------------------------------
# 3) Download and build Deluge
# -----------------------------------------------------------------------------
build_deluge() {
    echo "====> Downloading and building Deluge $DELUGE_VERSION"
    local SRC_DIR="$BASE_DIR/deluge-$DELUGE_VERSION"
    echo "====> Cleaning any existing Deluge directories"
    cd "$BASE_DIR"
    rm -rf deluge-*
    echo "====> Downloading Deluge"
    git clone --depth 1 --branch "$TAG" "https://github.com/deluge-torrent/deluge.git" "$SRC_DIR"
    cd "$SRC_DIR"
    git --no-pager log -1 --oneline
    echo "====> Installing Deluge"
    ${PYTHON_CMD} setup.py build
    DESTDIR="$INSTALL_DIR" ${PYTHON_CMD} setup.py install --prefix=$PREFIX
    cd "$WHEREAMI"
}

# -----------------------------------------------------------------------------
# 4) Créer le package final
# -----------------------------------------------------------------------------
create_package() {
    echo "====> Creating Deluge package"
    if [ ! -f "$INSTALL_DIR$PREFIX/bin/deluged" ] || [ ! -f "$INSTALL_DIR$PREFIX/bin/deluge-web" ]; then
        echo "ERROR: Deluge executables not found at $INSTALL_DIR$PREFIX/bin/deluged or $INSTALL_DIR$PREFIX/bin/deluge-web"
        echo "Compilation might have failed."
        exit 1
    fi
    echo "====> Deluge executables information:"
    file "$INSTALL_DIR$PREFIX/bin/deluged"
    file "$INSTALL_DIR$PREFIX/bin/deluge-web"
    echo "====> Copying Deluge executables to output directory"
    mkdir -p "$WHEREAMI/output"
    local EXECUTABLES=("deluged" "deluge-web" "deluge-console" "deluge-gtk")
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
        local PKG_DIR="$BASE_DIR/deb-pkg"
        local PACKAGE_NAME="deluge-${STABILITY}_${DELUGE_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
        rm -rf "$PKG_DIR"
        mkdir -p "$PKG_DIR/DEBIAN"
        local INSTALL_PATH="/opt/MediaEase/.binaries/installed/deluge-${STABILITY}_${DELUGE_VERSION}"
        mkdir -p "$PKG_DIR/$INSTALL_PATH"
        cp -r "$INSTALL_DIR$PREFIX" "$PKG_DIR/$INSTALL_PATH/"
        find "$PKG_DIR" -type f -exec file {} \; | grep ELF | cut -d: -f1 | xargs --no-run-if-empty strip --strip-unneeded
        local INSTALLED_SIZE=$(du -sk "$PKG_DIR/opt" | cut -f1)
        cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: deluge
Version: $FULL_VERSION
Architecture: $ARCHITECTURE
Maintainer: ${COMMITTER_NAME} <${COMMITTER_EMAIL}>
Installed-Size: ${INSTALLED_SIZE}
Depends: python3, python3-twisted, python3-openssl, python3-xdg, python3-chardet, python3-setproctitle, python3-rencode, python3-pillow, libtorrent-rasterbar-mediaease (>= ${LIBTORRENT_VERSION}), libssl3, libc6, zlib1g
Section: net
Priority: optional
Homepage: https://deluge-torrent.org/
Description: BitTorrent client (CLI tools, daemon and web UI)
 Deluge BitTorrent client compiled for server usage.
 Contains CLI tools, daemon and web interface.
 .
 This package contains:
  * CLI tools: deluge-console
  * Daemon: deluged
  * Web UI: deluge-web
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
export PYTHONPATH="${INSTALL_USR}/lib/python3/dist-packages:\$PYTHONPATH"
EOF2
        for bin in deluged deluge-web deluge-console deluge-gtk; do
            if [ -f "${INSTALL_USR}/bin/${bin}" ]; then
                update-alternatives --install "/usr/bin/${bin}" "${bin}" "${INSTALL_USR}/bin/${bin}" ${PRIORITY}
            fi
        done
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
        PKG_NAME="${DPKG_MAINTSCRIPT_PACKAGE:-deluge-stable}"
        PKG_VERSION="$(dpkg-query -W -f='${Version}' "${PKG_NAME}")"
        BASE_VERSION="${PKG_VERSION%-*}"
        INSTALL_BASE="/opt/MediaEase/.binaries/installed/${PKG_NAME}_${BASE_VERSION}"
        INSTALL_USR="${INSTALL_BASE}/usr"
        
        # Supprimer les alternatives pour les binaires
        for bin in deluged deluge-web deluge-console deluge-gtk; do
            if [ -f "${INSTALL_USR}/bin/${bin}" ]; then
                update-alternatives --remove "${bin}" "${INSTALL_USR}/bin/${bin}" || true
            fi
        done
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
install_dependencies
install_libtorrent
build_deluge
create_package

echo "====> All done! Deluge $DELUGE_VERSION has been built."
echo "====> The binaries are at $WHEREAMI/output/"
if [ -n "$CREATE_DEB" ] && [ "$CREATE_DEB" = "true" ]; then
    echo "====> The Debian package is at $WHEREAMI/output/deluge-${STABILITY}_${DELUGE_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
fi
exit 0 
