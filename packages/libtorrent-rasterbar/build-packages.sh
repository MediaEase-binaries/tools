#!/usr/bin/env bash
set -e

# =============================================================================
# build-packages.sh
#
# Ce script crée les packages Debian (.deb) pour libtorrent-rasterbar et
# ses bindings Python à partir des fichiers compilés précédemment.
#
# Usage:
# ./build-packages.sh <VERSION>
# Exemple:
# ./build-packages.sh 2.0.9
#
# Notes:
# - Nécessite que les scripts build-lib.sh et build-bindings.sh aient été
#   exécutés au préalable
# - Crée deux packages: libtorrent-rasterbar et python3-libtorrent
# - Les packages installent dans /usr/local/ pour compatibilité avec les builds personnalisés
# =============================================================================

usage() {
    echo "Usage: $0 <VERSION>"
    echo "Example: $0 2.0.9"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

# -----------------------------------------------------------------------------
# 0) Paramètres et variables globales
# -----------------------------------------------------------------------------
INPUT_VERSION="$1"                        # Ex: "2.0.9"
LIBTORRENT_VERSION="${INPUT_VERSION}"
BUILD="1build1"
FULL_VERSION="${LIBTORRENT_VERSION}-${BUILD}"
SOVERSION="${LIBTORRENT_VERSION%.*}"      # Ex: 2.0 from 2.0.9

echo "====> Creating packages for libtorrent-rasterbar $LIBTORRENT_VERSION (build: $BUILD)"
echo "====> Full version: $FULL_VERSION"
echo "====> SO version: $SOVERSION"

WHEREAMI="$(dirname "$(readlink -f "$0")")"
ARCHITECTURE="amd64"
PREFIX="/usr/local"
BASE_DIR="$PWD/custom_build"

# Répertoires d'installation (depuis les scripts précédents)
INSTALL_DIR="$BASE_DIR/install"
INSTALL_DIR_PYTHON="$BASE_DIR/install-python"

# Répertoires pour la construction des packages
DEBIAN_DIR="$BASE_DIR/debian"
mkdir -p "$DEBIAN_DIR/DEBIAN"
DEBIAN_DIR_PYTHON="$BASE_DIR/debian-python"
mkdir -p "$DEBIAN_DIR_PYTHON/DEBIAN"

# -----------------------------------------------------------------------------
# 1) Vérifier les prérequis
# -----------------------------------------------------------------------------
check_prereqs() {
    echo "====> Checking prerequisites"
    
    # Vérifier si les fichiers de libtorrent-rasterbar sont présents
    if [ ! -f "$INSTALL_DIR$PREFIX/include/libtorrent/torrent_handle.hpp" ] || [ ! -f "$INSTALL_DIR$PREFIX/lib/libtorrent-rasterbar.so" ]; then
        echo "ERROR: libtorrent-rasterbar files not found in $INSTALL_DIR$PREFIX."
        echo "Please run build-lib.sh first to compile the library."
        exit 1
    fi
    
    # Vérifier si les bindings Python sont présents
    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    if [ ! -f "$INSTALL_DIR_PYTHON$PREFIX/lib/python$PYTHON_VERSION/dist-packages/libtorrent.so" ]; then
        echo "ERROR: Python bindings not found in $INSTALL_DIR_PYTHON$PREFIX/lib/python$PYTHON_VERSION/dist-packages/."
        echo "Please run build-bindings.sh first to compile the Python bindings."
        exit 1
    fi
    
    echo "====> Prerequisites OK"
}

# -----------------------------------------------------------------------------
# 2) Créer le package Debian pour libtorrent-rasterbar
# -----------------------------------------------------------------------------
create_lib_package() {
    echo "====> Creating libtorrent-rasterbar Debian package"
    
    # Nettoyer le répertoire existant
    rm -rf "$DEBIAN_DIR"
    mkdir -p "$DEBIAN_DIR/DEBIAN"
    
    # Create DEBIAN control file
    cat > "$DEBIAN_DIR/DEBIAN/control" << EOF
Package: libtorrent-rasterbar
Version: $FULL_VERSION
Architecture: $ARCHITECTURE
Maintainer: ${COMMITTER_NAME} <${COMMITTER_EMAIL}>
Installed-Size: CHANGE_HERE
Description: C++ bittorrent library by Rasterbar Software
 Bittorrent library by Rasterbar Software (Arvid Norberg).
 libtorrent-rasterbar is a C++ library that aims to be a good alternative to
 all the other bittorrent implementations around.
 .
 The main goals of libtorrent-rasterbar are:
  * to be cpu efficient
  * to be memory efficient
  * to be very easy to use
 .
 This package contains both the shared library and development files.
 All files are installed in /usr/local/ for compatibility with custom builds.
Depends: libssl3, libstdc++6 (>= 11), libgcc-s1 (>= 3.4), libc6 (>= 2.34)
Suggests: python3-libtorrent
Section: libs
Priority: optional
Homepage: https://libtorrent.org/
EOF
    
    # Create postinst script
    cat > "$DEBIAN_DIR/DEBIAN/postinst" << EOF
#!/bin/sh
set -e
ldconfig
EOF
    chmod 755 "$DEBIAN_DIR/DEBIAN/postinst"
    
    # Create postrm script
    cat > "$DEBIAN_DIR/DEBIAN/postrm" << EOF
#!/bin/sh
set -e
ldconfig
EOF
    chmod 755 "$DEBIAN_DIR/DEBIAN/postrm"
    
    # Create shlibs file
    cat > "$DEBIAN_DIR/DEBIAN/shlibs" << EOF
libtorrent-rasterbar $SOVERSION libtorrent-rasterbar (>= $LIBTORRENT_VERSION)
EOF
    
    # Copy files from INSTALL_DIR to DEBIAN_DIR
    echo "====> Copying files from $INSTALL_DIR to $DEBIAN_DIR"
    rsync -a "$INSTALL_DIR"/ "$DEBIAN_DIR"/
    
    # Calculer la taille installée
    installed_size=$(du -s -k "$DEBIAN_DIR" | cut -f1)
    sed -i "s/CHANGE_HERE/$installed_size/" "$DEBIAN_DIR/DEBIAN/control"
    
    # Generate md5sums file
    cd "$DEBIAN_DIR"
    find . -type f -exec file {} \; | grep ELF | cut -d: -f1 | xargs --no-run-if-empty strip --strip-unneeded
    find . -type f ! -path "./DEBIAN/*" -exec md5sum {} \; > DEBIAN/md5sums
    
    # Build the package
    cd "$WHEREAMI"
    dpkg-deb --build -Zxz -z9 -Sextreme --root-owner-group "$DEBIAN_DIR" "$WHEREAMI/libtorrent-rasterbar_${LIBTORRENT_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
    
    echo "====> Debian package created: libtorrent-rasterbar_${LIBTORRENT_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
}

# -----------------------------------------------------------------------------
# 3) Créer le package Debian pour python3-libtorrent
# -----------------------------------------------------------------------------
create_python_package() {
    echo "====> Creating python3-libtorrent Debian package"
    
    # Nettoyer le répertoire existant
    rm -rf "$DEBIAN_DIR_PYTHON"
    mkdir -p "$DEBIAN_DIR_PYTHON/DEBIAN"
    
    # Déterminer la version de Python
    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    
    # Create DEBIAN control file
    cat > "$DEBIAN_DIR_PYTHON/DEBIAN/control" << EOF
Package: python3-libtorrent
Version: $FULL_VERSION
Architecture: $ARCHITECTURE
Maintainer: ${COMMITTER_NAME} <${COMMITTER_EMAIL}>
Installed-Size: CHANGE_HERE
Description: Python bindings for libtorrent-rasterbar (Python 3)
 Bittorrent library by Rasterbar Software (Arvid Norberg).
 libtorrent-rasterbar is a C++ library that aims to be a good alternative to
 all the other bittorrent implementations around.
 .
 The main goals of libtorrent-rasterbar are:
  * to be cpu efficient
  * to be memory efficient
  * to be very easy to use
 .
 This package contains Python 3 bindings for the libtorrent-rasterbar library.
 All files are installed in /usr/local/ for compatibility with custom builds.
Depends: libtorrent-rasterbar (>= $LIBTORRENT_VERSION), python3 (>= 3.7), libssl3, libstdc++6 (>= 11)
Section: python
Priority: optional
Homepage: https://libtorrent.org/
EOF
    
    # Copy files from INSTALL_DIR_PYTHON to DEBIAN_DIR_PYTHON
    echo "====> Copying files from $INSTALL_DIR_PYTHON to $DEBIAN_DIR_PYTHON"
    rsync -av "$INSTALL_DIR_PYTHON/" "$DEBIAN_DIR_PYTHON/"
    
    # Vérifier que les fichiers ont bien été copiés
    echo "====> Verifying Python files in Debian package"
    find "$DEBIAN_DIR_PYTHON" -name "libtorrent*.so"
    
    # Calculer la taille installée
    installed_size=$(du -s -k "$DEBIAN_DIR_PYTHON" | cut -f1)
    sed -i "s/CHANGE_HERE/$installed_size/" "$DEBIAN_DIR_PYTHON/DEBIAN/control"
    
    # Generate md5sums file
    cd "$DEBIAN_DIR_PYTHON"
    find . -type f -exec file {} \; | grep ELF | cut -d: -f1 | xargs --no-run-if-empty strip --strip-unneeded
    find . -type f ! -path "./DEBIAN/*" -exec md5sum {} \; > DEBIAN/md5sums
    
    # Build the package
    cd "$WHEREAMI"
    dpkg-deb --build -Zxz -z9 -Sextreme --root-owner-group "$DEBIAN_DIR_PYTHON" "$WHEREAMI/python3-libtorrent_${LIBTORRENT_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
    
    echo "====> Debian package created: python3-libtorrent_${LIBTORRENT_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
    
    # Vérifier le contenu du package créé
    echo "====> Package contents:"
    dpkg-deb -c "$WHEREAMI/python3-libtorrent_${LIBTORRENT_VERSION}-${BUILD}_${ARCHITECTURE}.deb" | grep -i libtorrent
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------
check_prereqs
create_lib_package
create_python_package

echo "====> All done! Packages created:"
echo "====> - libtorrent-rasterbar_${LIBTORRENT_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
echo "====> - python3-libtorrent_${LIBTORRENT_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
exit 0 
