#!/usr/bin/env bash
set -e

# =============================================================================
# build_all.sh
#
# This script bundles the building of dependencies and rtorrent. 
#
# It performs:
# - Compilation/installation of libudns, xmlrpc-c, mktorrent, and libtorrent
# - Compilation of rtorrent with dual installation:
# - Live installation in the /opt/MediaEase/.binaries/installed/... prefix
# - Staging installation via DESTDIR for final packaging
#
# The final package will contain all components and include:
# - A generated md5sums file
# - Postinst and prerm scripts to manage update-alternatives
#
# Usage:
# ./build_all.sh <VERSION_WITH_OPTIONAL_BUILD>
# Example:
# ./build_all.sh 0.13.8 or 0.14.0
#
# Notes:
# - For rtorrent 0.9.8, xmlrpc-c 1.59.4 is used. # - For rtorrent 0.10.0 or 0.15.1, xmlrpc-c 1.64.1 is used.
# - All configures use the following prefix:
# /opt/MediaEase/.binaries/installed/rtorrent-${PACKAGE_STABILITY}_${RT_VER}
# =============================================================================

usage() {
    echo "Usage: $0 <VERSION_WITH_OPTIONAL_BUILD>"
    echo "Exemple: $0 0.13.8-1 ou 0.14.0"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

# -----------------------------------------------------------------------------
# 0) Parameter analysis and definition of global variables
# -----------------------------------------------------------------------------
INPUT_VERSION="$1"                           # Ex: "0.13.8-1" or "0.14.0"
REAL_VERSION="${INPUT_VERSION%%-*}"          # Ex: "0.13.8"
BUILD="${INPUT_VERSION#*-}"                  # Build part, défault "1"
if [ "$BUILD" = "$REAL_VERSION" ]; then
    BUILD="1build1"
fi
FULL_VERSION="${REAL_VERSION}-${BUILD}"      # Ex: "0.13.8-1"

echo "====> Building rtorrent $REAL_VERSION (build: $BUILD)"
echo "====> Full version: $FULL_VERSION"
MINOR="$(echo "$REAL_VERSION" | cut -d'.' -f2)"
case "$MINOR" in
    9)
        RT_VER="0.9.8"
        LIBTORRENT_VERSION="0.13.8"
        PACKAGE_STABILITY="oldstable"
        FLTO=$(nproc)
        ;;
    10)
        RT_VER="0.10.0"
        LIBTORRENT_VERSION="0.14.0"
        PACKAGE_STABILITY="stable"
        FLTO=$(nproc)
        ;;
    15)
        RT_VER="0.15.2"
        LIBTORRENT_VERSION="0.15.2"
        PACKAGE_STABILITY="next"
        FLTO=$(nproc)
        ;;
    *)
        echo "ERROR: Unrecognized version '$REAL_VERSION' (expected 0.13.8, 0.10.0 or 0.15.1)."
        exit 1
        ;;
esac
if [ "$MINOR" -ge 15 ]; then
    XMLRPC_TINYXML="--with-xmlrpc-tinyxml2"
else
    XMLRPC_TINYXML="--with-xmlrpc-c"
fi

WHEREAMI="$(dirname "$(readlink -f "$0")")"
ARCHITECTURE="amd64"
PREFIX_BASE="/opt/MediaEase/.binaries/installed/rtorrent-${PACKAGE_STABILITY}_${RT_VER}"
BASE_DIR="$PWD/custom_build"
mkdir -p "$BASE_DIR"
INSTALL_DIR="$BASE_DIR/install"
mkdir -p "$INSTALL_DIR"
PATCH_DIR="$BASE_DIR/patches"
# find the extras dir
EXTRAS_DIR="$(find /home/runner/work/ -type d -name "extras" | head -n 1)"
EXTRAS_DIR="$EXTRAS_DIR/rtorrent"

# -----------------------------------------------------------------------------
# 1) Dumptorrent build
# -----------------------------------------------------------------------------
build_dumptorrent() {
    echo "====> Building dumptorrent"
    local TMP_DIR
    TMP_DIR=$(mktemp -d)
    dpkg-deb -x "$EXTRAS_DIR"/dumptorrent*.deb "$TMP_DIR"
    mkdir -p "$INSTALL_DIR/usr/local/bin"
    chmod +x "$TMP_DIR/usr/bin/*"
    sudo cp -r "$TMP_DIR/usr/*" "$INSTALL_DIR/usr/local/bin/"
    local DUMPTORRENT_VERSION
    DUMPTORRENT_VERSION=$(basename "$EXTRAS_DIR"/dumptorrent*.deb | sed -n 's/.*dumptorrent_\([^-]*\)-.*/\1/p')
    export DUMPTORRENT_VERSION
}

# -----------------------------------------------------------------------------
# 1) Libudns build
# -----------------------------------------------------------------------------
build_libudns() {
    echo "====> Building libudns"
    sudo dpkg -i "$EXTRAS_DIR/libudns_0.6.0-ipv6-ON-1build1_ubuntu-latest_amd64.deb"
    local TMP_DIR
    TMP_DIR=$(mktemp -d)
    dpkg-deb -x "$EXTRAS_DIR/libudns_0.6.0-ipv6-ON-1build1_ubuntu-latest_amd64.deb" "$TMP_DIR"
    sudo cp -r "$TMP_DIR/usr/" "$INSTALL_DIR/usr/"
    local LIBUDNS_VERSION
    LIBUDNS_VERSION="$(dpkg-query -W -f='${Version}' libudns)"
    export LIBUDNS_VERSION
}

# -----------------------------------------------------------------------------
# 2) xmlrpc-c build
# -----------------------------------------------------------------------------
build_xmlrpc() {
    echo "====> Building xmlrpc-c"
    local XMLRPC_VERSION
    if [ "$RT_VER" = "0.9.8" ]; then
        XMLRPC_VERSION="1.59.04"
    elif [ "$RT_VER" = "0.10.0" ]; then
        XMLRPC_VERSION="1.64.01"
    fi
    if [ -n "$XMLRPC_VERSION" ]; then
        local PKGNAME="xmlrpc-c"
        local PKGFILE="$(find "$EXTRAS_DIR" -name "${PKGNAME}_${XMLRPC_VERSION}*.deb" | head -n 1)"
        if [ -z "$PKGFILE" ]; then
            echo "ERROR: Unable to find xmlrpc-c package file."
            exit 1
        fi
        sudo dpkg -i "$PKGFILE"
        local TMP_DIR
        TMP_DIR=$(mktemp -d)
        dpkg-deb -x "$PKGFILE" "$TMP_DIR"
        sudo cp -r "$TMP_DIR/usr/" "$INSTALL_DIR/usr/"
        rm -rf "$TMP_DIR"
        export XMLRPC_VERSION
    else
        export TINYXML2_USED="true"
    fi
}

# -----------------------------------------------------------------------------
# 3) mktorrent build
# -----------------------------------------------------------------------------
build_mktorrent() {
    echo "====> Building mktorrent"
    sudo dpkg -i "$EXTRAS_DIR"/mktorrent*.deb
    local MKTORRENT_VERSION
    MKTORRENT_VERSION="$(dpkg-query -W -f='${Version}' mktorrent)"
    local TMP_DIR
    TMP_DIR=$(mktemp -d)
    dpkg-deb -x "$EXTRAS_DIR"/mktorrent*.deb "$TMP_DIR"
    sudo cp -r "$TMP_DIR/usr/" "$INSTALL_DIR/usr/"
    rm -rf "$TMP_DIR"
    export MKTORRENT_VERSION
}

# -----------------------------------------------------------------------------
# 4) libtorrent (rakshasa) build
# -----------------------------------------------------------------------------
build_libtorrent() {
    echo "====> Building libtorrent (version $LIBTORRENT_VERSION)"
    local GIT_REPO_URL="https://github.com/rakshasa/libtorrent.git"
    local SRC_DIR="$BASE_DIR/libtorrent-rakshasa-$LIBTORRENT_VERSION"
    rm -rf "$SRC_DIR"
    git clone --depth 1 --branch "v${LIBTORRENT_VERSION}" "$GIT_REPO_URL" "$SRC_DIR"
    cd "$SRC_DIR"
    git --no-pager log -1 --oneline
    if [ "$LIBTORRENT_VERSION" = "0.13.8" ]; then
        local PATCH_DIR="$PATCH_DIR/libtorrent"
        echo "Applying patches for libtorrent 0.13.8..."
        for patch in udns scanf lookup-cache piece-boundary; do
            if [ -f "$PATCH_DIR/${patch}-0.13.8.patch" ]; then
                patch -p1 --fuzz=3 --ignore-whitespace --verbose --unified < "$PATCH_DIR/${patch}-0.13.8.patch" || true
            fi
        done
    fi
    if [ -f ./autogen.sh ]; then
        if ! grep -q "AC_CONFIG_MACRO_DIRS" configure.ac; then
            sed -i '2iAC_CONFIG_MACRO_DIRS([scripts])' configure.ac
        fi
        ./autogen.sh
    else
        wget -O autogen.sh 'https://github.com/rakshasa/libtorrent/blob/2ce482a3bea8a5f051d2595fad5a1d19c6f10471/autogen.sh?raw=true'
        chmod +x autogen.sh
        ./autogen.sh
    fi
    autoreconf -vfi
    ./configure \
        --prefix="$PREFIX_BASE" \
        --disable-debug \
        --with-posix-fallocate \
        --enable-aligned \
        --enable-static \
        --disable-shared
    make -j"$FLTO"
    make install DESTDIR="$INSTALL_DIR"
    make clean
    make distclean
    ./configure \
        --disable-debug \
        --with-posix-fallocate \
        --enable-aligned \
        --enable-static \
        --disable-shared
    make -j"$FLTO"
    sudo make install
    cd "$WHEREAMI"
}

# -----------------------------------------------------------------------------
# 5) rtorrent build
# -----------------------------------------------------------------------------
build_rtorrent() {
    echo "====> Building rtorrent"
    local GIT_REPO_URL="https://github.com/rakshasa/rtorrent.git"
    local SRC_DIR="$BASE_DIR/rtorrent-$REAL_VERSION"
    rm -rf "$SRC_DIR"
    git clone --depth 1 --branch "v$RT_VER" "$GIT_REPO_URL" "$SRC_DIR"
    cd "$SRC_DIR"
    git --no-pager log -1 --oneline
    export CFLAGS="-Os -DNDEBUG -g0 -ffunction-sections -fdata-sections"
    export LDFLAGS="-Wl,--gc-sections -s -lssl -lcrypto -lz"
    export LIBS="$LIBS -lssl -lcrypto -lz"
    if [ "$REAL_VERSION" = "0.13.8" ]; then
        echo "Applying patches for rtorrent 0.13.8..."
        local PATCH_DIR="$PATCH_DIR/rtorrent"
        for patch in fast-session-loading lockfile lockfile rtorrent-ml rtorrent-scrape scgi session-file; do
            if [ -f "$PATCH_DIR/${patch}-0.13.8.patch" ]; then
                patch -p1 --fuzz=3 --ignore-whitespace --verbose --unified < "$PATCH_DIR/${patch}-0.13.8.patch" || true
            fi
        done
    fi
    [[ -f ./autogen.sh ]] && ./autogen.sh || true
    autoreconf -vfi
    ./configure --with-ncursesw --prefix="$PREFIX_BASE" $XMLRPC_TINYXML
    local mem_available_kb
    mem_available_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    local mem_available_mb=$((mem_available_kb / 1024))
    local rtorrent_level=""
    local rtorrent_flto=""
    local rtorrent_pipe=""
    local rtorrent_profile="-fprofile-use"
    case "$FLTO" in
        1)
            rtorrent_level="-O1"
        ;;
        [2-3])
            rtorrent_level="-O2"
        ;;
        [4-7])
            rtorrent_level="-O2"
            rtorrent_flto="-flto=$FLTO"
        ;;
        *)
            rtorrent_level="-O3"
            rtorrent_flto="-flto=$FLTO"
        ;;
    esac
    if [ "$mem_available_mb" -gt 512 ]; then
        rtorrent_pipe="-pipe"
    fi
    make -j"$FLTO" CXXFLAGS="-w $rtorrent_level $rtorrent_flto $rtorrent_pipe $rtorrent_profile"
    make install DESTDIR="$INSTALL_DIR"
    make clean
    make distclean
    ./configure --with-ncursesw  $XMLRPC_TINYXML
    make -j"$FLTO" CXXFLAGS="-w $rtorrent_level $rtorrent_flto $rtorrent_pipe $rtorrent_profile"
    sudo make install
    cd "$WHEREAMI"
}

# -----------------------------------------------------------------------------
# 6) Final packaging
# -----------------------------------------------------------------------------
package_rtorrent_deb() {
    echo "====> Packaging rtorrent to .deb file"
    local PKG_DIR="$BASE_DIR/pkg_rtorrent"
    rm -rf "$PKG_DIR"
    mkdir -p "$PKG_DIR/DEBIAN"
    cp -r "$INSTALL_DIR/opt" "$PKG_DIR/"
    find "$PKG_DIR"  -type f -exec file {} \;   | grep ELF   | cut -d: -f1   | xargs --no-run-if-empty strip --strip-unneeded
    find "$PKG_DIR" -type f ! -path './DEBIAN/*' -exec md5sum {} \; > "$PKG_DIR/DEBIAN/md5sums"
    local runtime_size
    runtime_size=$(du -s -k "$PKG_DIR/opt" | cut -f1)
    if [ "$TINYXML2_USED" == true ]; then
        VERSION="$(dpkg-query -W -f='${Version}' tinyxml2 2>/dev/null || echo 'unknown')"
        TINY_OR_XMLRPC="tinyxml2 ($VERSION)"
    else
        TINY_OR_XMLRPC="xmlrpc-c ($XMLRPC_VERSION)"
    fi
    cat <<EOF > "$PKG_DIR/DEBIAN/control"
Package: rtorrent-${PACKAGE_STABILITY}
Version: $REAL_VERSION
Architecture: $ARCHITECTURE
Maintainer: ${COMMITTER_NAME} <${COMMITTER_EMAIL}>
Installed-Size: $runtime_size
Depends: libc6 (>= 2.36), libncurses
Section: net
Priority: optional
Homepage: https://rakshasa.github.io/rtorrent/
Description: ncurses BitTorrent client based on LibTorrent from rakshasa
  rtorrent is a BitTorrent client based on LibTorrent.  It uses ncurses
  and aims to be a lean, yet powerful BitTorrent client, with features
  similar to the most complex graphical clients.
  .
  Since it is a terminal application, it can be used with the "screen"/"dtach"
  utility so that the user can conveniently logout from the system while keeping
  the file transfers active.
  .
  Some of the features of rtorrent include:
   * Use an URL or file path to add torrents at runtime
   * Stop/delete/resume torrents
   * Optionally loads/saves/deletes torrents automatically in a session
     directory
   * Safe fast resume support
   * Detailed information about peers and the torrent
   * Support for distributed hash tables (DHT)
   * Support for peer-exchange (PEX)
   * Support for initial seeding (Superseeding)
  .
  This build includes :
   * libtorrent (= $LIBTORRENT_VERSION)
   * $TINY_OR_XMLRPC, 
   * mktorrent (= $MKTORRENT_VERSION), 
   * libudns (= $LIBUDNS_VERSION),
   * dumptorrent (= $DUMPTORRENT_VERSION).
  .
  It is optimized for performance and ready for use with MediaEase.
  .
  Compiled on $(date +%Y-%m-%d)
EOF
    echo "Generating md5sums..."
    (
        cd "$PKG_DIR"
        find . -type f ! -path "./DEBIAN/*" -exec md5sum {} \; > DEBIAN/md5sums
    )
    cat <<'EOF' > "$PKG_DIR/DEBIAN/postinst"
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
        if [ -d "${INSTALL_USR}/include/torrent" ]; then
            update-alternatives --install \
                /usr/include/torrent torrent \
                "${INSTALL_USR}/include/torrent" ${PRIORITY}
        fi
        if [ -f "${INSTALL_USR}/lib/pkgconfig/libtorrent.pc" ]; then
            update-alternatives --install \
                /usr/lib/x86_64-linux-gnu/pkgconfig/libtorrent.pc libtorrent.pc \
                "${INSTALL_USR}/lib/pkgconfig/libtorrent.pc" ${PRIORITY}
        fi
        cat > "${ENV_FILE}" <<EOF2
export CPATH="${INSTALL_BASE}/include:\$CPATH"
export C_INCLUDE_PATH="${INSTALL_BASE}/include:\$C_INCLUDE_PATH"
export CPLUS_INCLUDE_PATH="${INSTALL_BASE}/include:\$CPLUS_INCLUDE_PATH"
export LIBRARY_PATH="${INSTALL_BASE}/lib:\$LIBRARY_PATH"
export LD_LIBRARY_PATH="${INSTALL_BASE}/lib:\$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="${INSTALL_BASE}/lib/pkgconfig:\$PKG_CONFIG_PATH"
export PATH="${INSTALL_BASE}/bin:\$PATH"
EOF2
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
    cat <<'EOF' > "$PKG_DIR/DEBIAN/prerm"
#!/bin/sh
set -e
case "$1" in
    remove|deconfigure)
        PKG_NAME="${DPKG_MAINTSCRIPT_PACKAGE:-rtorrent-stable}"
        PKG_VERSION="$(dpkg-query -W -f='${Version}' "${PKG_NAME}")"
        BASE_VERSION="${PKG_VERSION%-*}"
        INSTALL_BASE="/opt/MediaEase/.binaries/installed/${PKG_NAME}_${BASE_VERSION}"
        INSTALL_USR="${INSTALL_BASE}/usr"
        if [ -d "${INSTALL_USR}/include/torrent" ]; then
            update-alternatives --remove torrent "${INSTALL_USR}/include/torrent" || true
        fi
        if [ -f "${INSTALL_USR}/lib/pkgconfig/libtorrent.pc" ]; then
            update-alternatives --remove libtorrent.pc "${INSTALL_USR}/lib/pkgconfig/libtorrent.pc" || true
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
    chmod 755 "$PKG_DIR/DEBIAN/postinst" "$PKG_DIR/DEBIAN/prerm"
    package_name="rtorrent-${PACKAGE_STABILITY}_${REAL_VERSION}_lt${LIBTORRENT_VERSION}-1build1_${ARCHITECTURE}.deb"
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
build_libudns
build_xmlrpc
build_mktorrent
build_libtorrent
build_rtorrent
package_rtorrent_deb

echo "====> rtorrent $FULL_VERSION has been built and packaged successfully."
