#!/usr/bin/env bash
set -e

# =============================================================================
# build.sh
#
# This script builds the latest version of Boost and packages it as a .deb file
# that installs to /tmp/boost.
#
# Usage:
# ./build.sh <VERSION>
# Example:
# ./build.sh 1.84.0 or 1.88.0_rc1
#
# Notes:
# - Installs to /tmp/boost (temporary location for libtorrent-rasterbar builds)
# - Creates a Debian package for easy installation/uninstallation
# =============================================================================

usage() {
    echo "Usage: $0 <VERSION>"
    echo "Example: $0 1.84.0 or 1.88.0_rc1"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

# -----------------------------------------------------------------------------
# 0) Parameter analysis and definition of global variables
# -----------------------------------------------------------------------------
INPUT_VERSION="$1"                           # Ex: "1.84.0" or "1.88.0_rc1"
BOOST_VERSION="${INPUT_VERSION}"
BUILD="1build1"
FULL_VERSION="${BOOST_VERSION//_rc[0-9]*/}-${BUILD}"

echo "====> Building boost $BOOST_VERSION (build: $BUILD)"
echo "====> Full version: $FULL_VERSION"

WHEREAMI="$(dirname "$(readlink -f "$0")")"
ARCHITECTURE="amd64"
PREFIX="/tmp/boost"
BASE_DIR="$PWD/custom_build"
mkdir -p "$BASE_DIR"
INSTALL_DIR="$BASE_DIR/install"
mkdir -p "$INSTALL_DIR"
DEBIAN_DIR="$BASE_DIR/debian"
mkdir -p "$DEBIAN_DIR/DEBIAN"

# Determine number of CPU cores for parallel build
CORES=$(nproc)

# -----------------------------------------------------------------------------
# 1) Download and extract Boost
# -----------------------------------------------------------------------------
build_boost() {
    echo "====> Downloading and extracting Boost $BOOST_VERSION"
    
    # Formater le nom du fichier en fonction de la version
    local VERSION_UNDERSCORE="${BOOST_VERSION//./_}"
    
    # Nettoyer les anciens fichiers boost_*
    echo "====> Cleaning any existing boost directories"
    cd "$BASE_DIR"
    rm -rf boost_*
    
    # Télécharger Boost
    echo "====> Downloading Boost"    
    if [[ "$BOOST_VERSION" == *"_rc"* ]]; then
        # Version candidate (RC)
        local BASE_VERSION=$(echo "$BOOST_VERSION" | sed 's/_rc[0-9]*//')
        echo "====> Using RC version: base=$BASE_VERSION, rc from $BOOST_VERSION"
        wget "https://archives.boost.io/release/$BASE_VERSION/source/boost_${VERSION_UNDERSCORE}.tar.gz" -O "boost.tar.gz"
    else
        # Version stable
        wget "https://archives.boost.io/release/$BOOST_VERSION/source/boost_${VERSION_UNDERSCORE}.tar.gz" -O "boost.tar.gz"
    fi
    
    # Extraire l'archive
    echo "====> Extracting archive"
    tar xzf "boost.tar.gz"
    rm "boost.tar.gz"
    
    # Trouver le répertoire réellement créé
    local SRC_DIR=$(find "$BASE_DIR" -maxdepth 1 -type d -name "boost_*" | head -n 1)
    
    if [ -z "$SRC_DIR" ]; then
        echo "ERROR: Could not find extracted Boost directory. Contents of $BASE_DIR:"
        ls -la "$BASE_DIR"
        exit 1
    fi
    
    echo "====> Found Boost source directory: $SRC_DIR"
    cd "$SRC_DIR" || { echo "Cannot change to directory $SRC_DIR"; exit 1; }
    
    # Bootstrap
    echo "====> Bootstrapping Boost"
    ./bootstrap.sh --with-libraries=system
    
    # Installation locale directe (pour créer la structure de répertoires)
    mkdir -p "$INSTALL_DIR$PREFIX"
    mkdir -p "$INSTALL_DIR$PREFIX/bin"
    mkdir -p "$INSTALL_DIR$PREFIX/share/boost-build"
    
    # Build with custom prefix for temporary installation
    echo "====> Building Boost with prefix $PREFIX and installing to $INSTALL_DIR$PREFIX"
    ./b2 -j"$CORES" \
        --prefix="$INSTALL_DIR$PREFIX" \
        --build-dir="$BASE_DIR/build" \
        variant=release \
        link=static,shared \
        runtime-link=shared \
        threading=multi \
        cxxflags="-std=c++11 -fPIC" \
        --layout=system \
        install
    
    # Copier les outils de build (b2, bjam) et les fichiers .jam
    echo "====> Copying build tools (b2, bjam) and .jam files"
    
    # Copier b2 et bjam
    cp -p "$SRC_DIR/b2" "$INSTALL_DIR$PREFIX/bin/"
    ln -sf "$PREFIX/bin/b2" "$INSTALL_DIR$PREFIX/bin/bjam"
    
    # Copier les fichiers .jam et autres fichiers de build
    cp -rp "$SRC_DIR/boost-build.jam" "$INSTALL_DIR$PREFIX/share/boost-build/"
    cp -rp "$SRC_DIR/boostcpp.jam" "$INSTALL_DIR$PREFIX/share/boost-build/"
    
    # Copier tools/build pour les règles de build
    mkdir -p "$INSTALL_DIR$PREFIX/share/boost-build/tools"
    cp -rp "$SRC_DIR/tools/build" "$INSTALL_DIR$PREFIX/share/boost-build/tools/"
    
    # Copier project-config.jam
    {
        echo "# Boost.Build Configuration"
        echo "# Automatically generated by boost-builds package"
        echo "import option ;"
        echo "import feature ;"
        echo "using gcc ;"
    } > "$INSTALL_DIR$PREFIX/share/boost-build/project-config.jam"
    
    # Créer un script wrapper pour b2
    cat > "$INSTALL_DIR$PREFIX/bin/b2-wrapper" << 'EOF'
#!/bin/bash
export BOOST_BUILD_PATH=/tmp/boost/share/boost-build
exec /tmp/boost/bin/b2 "$@"
EOF
    chmod +x "$INSTALL_DIR$PREFIX/bin/b2-wrapper"
    
    cd "$WHEREAMI"
}

# -----------------------------------------------------------------------------
# 2) Create Debian package
# -----------------------------------------------------------------------------
create_deb_package() {
    echo "====> Creating Debian package"
    
    # Vérifier que le répertoire d'installation contient des fichiers
    if [ ! -d "$INSTALL_DIR$PREFIX" ] || [ -z "$(ls -A "$INSTALL_DIR$PREFIX")" ]; then
        echo "ERROR: Installation directory $INSTALL_DIR$PREFIX is empty or does not exist!"
        echo "Contents of $INSTALL_DIR:"
        ls -la "$INSTALL_DIR"
        exit 1
    fi
    
    # Create package directories
    mkdir -p "$DEBIAN_DIR$PREFIX"
    
    # Create DEBIAN control file
    cat > "$DEBIAN_DIR/DEBIAN/control" << EOF
Package: boost-mediaease
Version: $FULL_VERSION
Architecture: $ARCHITECTURE
Maintainer: ${COMMITTER_NAME} <${COMMITTER_EMAIL}>
Description: Boost libraries (temporary installation for libtorrent-rasterbar builds)
 This package contains the Boost C++ libraries installed in /tmp/boost.
 It is intended to be used temporarily during the build process of
 libtorrent-rasterbar and is not meant for permanent installation.
 Includes the b2/bjam build tools and necessary .jam files.
Section: libs
Priority: optional
EOF
    
    # Create postinst script
    cat > "$DEBIAN_DIR/DEBIAN/postinst" << EOF
#!/bin/sh
set -e
chmod -R 755 $PREFIX
# Make sure the build tools are executable
chmod +x $PREFIX/bin/b2
chmod +x $PREFIX/bin/b2-wrapper
ln -sf $PREFIX/bin/b2 $PREFIX/bin/bjam
EOF
    chmod 755 "$DEBIAN_DIR/DEBIAN/postinst"
    
    # Create prerm script
    cat > "$DEBIAN_DIR/DEBIAN/prerm" << EOF
#!/bin/sh
set -e
# No specific actions needed
EOF
    chmod 755 "$DEBIAN_DIR/DEBIAN/prerm"
    
    # Copy files from INSTALL_DIR to DEBIAN_DIR
    echo "====> Copying files from $INSTALL_DIR$PREFIX to $DEBIAN_DIR$PREFIX"
    rsync -a "$INSTALL_DIR$PREFIX/" "$DEBIAN_DIR$PREFIX/"
    
    # Generate md5sums file
    cd "$DEBIAN_DIR"
    find .  -type f -exec file {} \; | grep ELF | cut -d: -f1 | xargs --no-run-if-empty strip --strip-unneeded
    find . -type f ! -path "./DEBIAN/*" -exec md5sum {} \; > DEBIAN/md5sums
    
    # Build the package
    cd "$WHEREAMI"
    dpkg-deb --build -Zxz -z9 -Sextreme --root-owner-group "$DEBIAN_DIR" "$WHEREAMI/boost-mediaease_${BOOST_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
    
    echo "====> Debian package created: boost-mediaease_${BOOST_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------
build_boost
create_deb_package

echo "====> All done!"
exit 0 
