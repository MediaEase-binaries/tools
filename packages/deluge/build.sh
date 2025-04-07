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
    "2.0.5") STABILITY="oldstable"; LIBTORRENT_VERSION="2.0.5"; TAG="deluge-2.0.5" ;;
    "2.1.0") STABILITY="oldstable"; LIBTORRENT_VERSION="${LIBTORRENT_VERSION:-2.0.9}"; TAG="deluge-2.1.0" ;;
    "2.1.1") STABILITY="stable";    LIBTORRENT_VERSION="2.0.11"; TAG="deluge-2.1.1" ;;
    "2.1.2.dev0") STABILITY="stable";    LIBTORRENT_VERSION="2.0.10"; TAG="deluge-2.1.2.dev0" ;;
    "2.2.0") STABILITY="next"; LIBTORRENT_VERSION="2.0.11"; TAG="develop" ;;
    *) echo "ERROR: Unsupported version: $DELUGE_VERSION"; exit 1 ;;
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
PYTHON_VERSION="3"
PYTHON_CMD="python${PYTHON_VERSION}"
LIBTORRENT_VERSION=$(${PYTHON_CMD} -c "import libtorrent as lt; print(lt.version)")

# -----------------------------------------------------------------------------
# 1) Download and build Deluge
# -----------------------------------------------------------------------------
build_deluge() {
    echo "====> Downloading and building Deluge $DELUGE_VERSION"
    local SRC_DIR="$BASE_DIR/deluge-$DELUGE_VERSION"
    echo "====> Cleaning any existing Deluge directories"
    cd "$BASE_DIR"
    rm -rf deluge-*
    echo "====> Downloading Deluge"
    git clone --recurse-submodules --branch "$TAG" https://github.com/deluge-torrent/deluge.git "$SRC_DIR"
    cd "$SRC_DIR"
    git fetch --tags
    git --no-pager log -1 --oneline
    echo "====> Installing Deluge"
    codename=$(lsb_release -cs)
    python_version=$(${PYTHON_CMD} --version 2>&1 | grep -oP 'Python \K[0-9]+\.[0-9]+')
    echo "====> Detected Python version: $python_version on $codename"
    packages=("pyopenssl" "service_identity" "pillow" "rencode" "pyxdg" "chardet" "setproctitle" "wheel" "cryptography")
    is_modern_os=false
    case "$codename" in
        buster|focal) 
            is_modern_os=false
            ;;
        bullseye|bookworm|jammy|noble|*) 
            is_modern_os=true
            packages+=("twisted")
            ;;
    esac
    echo "====> Installing Python packages: ${packages[*]}"
    break_system=""
    if $is_modern_os && python3 -m pip --version | grep -q "pip 2[3-9]"; then
        echo "====> Using --break-system-packages for modern pip"
        break_system="--break-system-packages"
    fi
    echo "====> Creating Python virtualenv"
    VENV_DIR="$BASE_DIR/venv"
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    echo "====> Installing dependencies in venv"
    for pkg in "${packages[@]}"; do
        echo "====> Installing $pkg"
        ${PYTHON_CMD} -m pip install "$pkg" $break_system
    done
    echo "====> Installing tox"
    ${PYTHON_CMD} -m pip install tox $break_system
    apt-get install -yqq --no-install-recommends python3-setuptools python3-wheel python3-pip --reinstall
    ${PYTHON_CMD} -m pip install --upgrade setuptools $break_system --use-deprecated=legacy-resolver
    ${PYTHON_CMD} -m pip install . --prefix="$PREFIX" --root="$INSTALL_DIR" $break_system --no-use-pep517
    deactivate
    cd "$WHEREAMI"
}

# -----------------------------------------------------------------------------
# 2) Create the package
# -----------------------------------------------------------------------------
create_package() {
    echo "====> Creating Deluge package"
    files=("deluged" "deluge-web" "deluge-console" "deluge-gtk" "deluge")
    mkdir -p "$WHEREAMI/output"
    for file in "${files[@]}"; do
        found=$(find "$INSTALL_DIR$PREFIX/bin" -name "$file" -type f | head -n1)
        if [ -n "$found" ]; then
            echo "====> Found $file at $found"
            file "$found"
            chmod +x "$found"
            cp "$found" "$WHEREAMI/output/"
        else
            found=$(find "$INSTALL_DIR" -name "$file" -type f | head -n1)
            if [ -n "$found" ]; then
                echo "====> Found $file at $found (alternative location)"
                file "$found"
                chmod +x "$found"
                cp "$found" "$WHEREAMI/output/"
            else
                echo "====> ERROR: $file not found in installation directory"
                echo "====> WARNING: Continuing without $file"
            fi
        fi
    done
    essential_files=("deluged" "deluge-web" "deluge-console")
    missing=0
    for efile in "${essential_files[@]}"; do
        if [ ! -f "$WHEREAMI/output/$efile" ]; then
            echo "====> ERROR: Essential file $efile is missing"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then
        echo "====> ERROR: Some essential files are missing, cannot continue"
    fi
    if [ -n "$CREATE_DEB" ] && [ "$CREATE_DEB" = "true" ]; then
        echo "====> Creating Debian package"
        local LIBTORRENT_DEB PYTHON_LIBTORRENT_DEB PACKAGE_NAME INSTALL_PATH libtorrent_files INSTALLED_SIZE PKG_DIR os_name codename os
        PKG_DIR="$BASE_DIR/deb-pkg"
        LIBTORRENT_DEB=$(find "/" -name "libtorrent*.deb" -type f | head -n1)
        PYTHON_LIBTORRENT_DEB=$(find "/" -name "python3-libtorrent*.deb" -type f | head -n1)
        os_name=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
        codename=$(lsb_release -cs)
        os="${os_name}-${codename}"
        PACKAGE_NAME="deluge-${STABILITY}_${DELUGE_VERSION}-${BUILD}_${os}_${ARCHITECTURE}.deb"
        INSTALL_PATH="/opt/MediaEase/.binaries/installed/deluge_${DELUGE_VERSION}_lt_${LIBTORRENT_VERSION}"
        rm -rf "$PKG_DIR"
        mkdir -p "$PKG_DIR/DEBIAN"
        mkdir -p "$PKG_DIR/$INSTALL_PATH"
        cp -r "$INSTALL_DIR$PREFIX" "$PKG_DIR/$INSTALL_PATH/"
        for deb in "$LIBTORRENT_DEB" "$PYTHON_LIBTORRENT_DEB"; do
            if [ -f "$deb" ]; then
                echo "====> Extracting $deb"
                local temp_extract
                temp_extract=$(mktemp -d)
                dpkg-deb -x "$deb" "$temp_extract"
                rm -rf "$temp_extract/DEBIAN"
                if [ -d "$temp_extract/usr" ]; then
                    cp -r "$temp_extract/usr"/* "$PKG_DIR/$INSTALL_PATH/usr/"
                fi
                rm -rf "$temp_extract"
            else
                echo "====> WARNING: $deb not found, skipping"
            fi
        done
        libtorrent_files=$(find "$PKG_DIR/$INSTALL_PATH" -name "libtorrent*" -type f)
        if [ -z "$libtorrent_files" ]; then
            echo "====> ERROR: No libtorrent files found in $PKG_DIR/$INSTALL_PATH"
            echo "====> This is required for Deluge to function properly"
            exit 1
        else
            echo "====> Found libtorrent files in $PKG_DIR/$INSTALL_PATH"
        fi
        find "$PKG_DIR" -type f -exec file {} \; | grep ELF | cut -d: -f1 | xargs --no-run-if-empty strip --strip-unneeded
        INSTALLED_SIZE=$(du -sk "$PKG_DIR/opt" | cut -f1)
        cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: deluge-${STABILITY}
Version: $FULL_VERSION
Architecture: $ARCHITECTURE
Maintainer: ${COMMITTER_NAME} <${COMMITTER_EMAIL}>
Installed-Size: ${INSTALLED_SIZE}
Depends: python3, python3-twisted, python3-openssl, python3-xdg, python3-chardet, python3-setproctitle, python3-rencode, python3-pillow, libssl3, libc6, zlib1g
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
        
        # Delete the alternatives for the binaries
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
build_deluge
create_package

echo "====> All done! Deluge $DELUGE_VERSION has been built."
echo "====> The binaries are at $WHEREAMI/output/"
if [ -n "$CREATE_DEB" ] && [ "$CREATE_DEB" = "true" ]; then
    echo "====> The Debian package is at $WHEREAMI/output/deluge-${STABILITY}_${DELUGE_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
fi
exit 0 
