#!/usr/bin/env bash
set -e

# =============================================================================
# build-lib.sh
#
# Ce script compile uniquement la bibliothèque libtorrent-rasterbar
# (sans créer de package Debian)
#
# Usage:
# ./build-lib.sh <VERSION>
# Exemple:
# ./build-lib.sh 2.0.9
#
# Notes:
# - Nécessite le package boost-mediaease (sera installé si absent)
# - Installe dans le répertoire ./custom_build/install uniquement
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

echo "====> Building libtorrent-rasterbar $LIBTORRENT_VERSION (build: $BUILD)"
echo "====> Full version: $FULL_VERSION"
echo "====> SO version: $SOVERSION"

WHEREAMI="$(dirname "$(readlink -f "$0")")"
PREFIX="/usr/local"
BASE_DIR="$PWD/custom_build"
mkdir -p "$BASE_DIR"

# Répertoires d'installation
INSTALL_DIR="$BASE_DIR/install"
mkdir -p "$INSTALL_DIR"

# Nombre de cœurs pour compilation parallèle
CORES=$(nproc)

# -----------------------------------------------------------------------------
# 1) Vérifier et installer boost-mediaease si nécessaire
# -----------------------------------------------------------------------------
install_boost() {
    echo "====> Checking if boost-mediaease is installed"
    
    # Utiliser uniquement Boost 1.88.0
    echo "====> Using Boost 1.88.0 for libtorrent $LIBTORRENT_VERSION"
    BOOST_VERSION="1.88.0"
    BOOST_VERSION_UNDERSCORED="1_88_0"
    BOOST_PACKAGE_NAME="boost-mediaease_1.88.0_rc1-1build1_amd64.deb"
    
    # Vérifier si le package boost-mediaease est installé avec la bonne version
    if dpkg -l | grep -q "boost-mediaease" && dpkg -l | grep "boost-mediaease" | grep -q "$BOOST_VERSION"; then
        echo "====> boost-mediaease $BOOST_VERSION is already installed"
    else
        echo "====> Installing boost-mediaease $BOOST_VERSION from tools directory"
        
        # Chercher le package boost-mediaease avec le nom exact
        local BOOST_PACKAGE="$WHEREAMI/tools/$BOOST_PACKAGE_NAME"
        
        if [ ! -f "$BOOST_PACKAGE" ]; then
            echo "ERROR: $BOOST_PACKAGE_NAME not found in the tools directory!"
            exit 1
        fi
        
        echo "====> Found boost package: $BOOST_PACKAGE"
        sudo dpkg -i "$BOOST_PACKAGE"
    fi
    
    # Vérifier que le répertoire /tmp/boost existe
    if [ ! -d "/tmp/boost" ]; then
        echo "ERROR: /tmp/boost directory not found, boost-mediaease might not be installed correctly!"
        exit 1
    fi
    
    # Vérifier si b2/bjam sont disponibles
    if [ ! -f "/tmp/boost/bin/b2" ] && [ ! -f "/tmp/boost/bin/bjam" ] && [ ! -f "/usr/local/bin/b2" ] && [ ! -f "/usr/local/bin/bjam" ]; then
        echo "====> b2/bjam not found, trying to build from source"
        
        # Télécharger et compiler Boost.Build
        cd /tmp
        if [ ! -d "boost-build" ]; then
            git clone --depth 1 https://github.com/boostorg/build.git boost-build
        fi
        
        cd boost-build
        ./bootstrap.sh
        sudo ./b2 install --prefix=/usr/local
        
        cd /tmp
        
        # Vérifier que b2 est maintenant disponible
        if [ ! -f "/usr/local/bin/b2" ]; then
            echo "ERROR: Failed to build b2"
            exit 1
        else
            echo "====> Successfully built and installed b2"
        fi
    fi
    
    # Créer des liens symboliques pour compatibilité avec Swizzin et autres scripts
    echo "====> Setting up compatibility links for Boost Build system"
    sudo mkdir -p /opt/boost_${BOOST_VERSION_UNDERSCORED}
    
    # Liens symboliques des en-têtes
    sudo ln -sf /tmp/boost/include/* /opt/boost_${BOOST_VERSION_UNDERSCORED}/
    
    # Liens symboliques des bibliothèques
    sudo ln -sf /tmp/boost/lib/* /opt/boost_${BOOST_VERSION_UNDERSCORED}/
    
    # Liens symboliques des outils de build
    if [ -f "/tmp/boost/bin/b2" ]; then
        echo "====> Found b2 at /tmp/boost/bin/b2, creating symlinks"
        sudo ln -sf /tmp/boost/bin/b2 /opt/boost_${BOOST_VERSION_UNDERSCORED}/b2
        sudo ln -sf /tmp/boost/bin/b2 /usr/local/bin/b2
    else
        echo "WARNING: Could not find b2 at /tmp/boost/bin/b2"
        find /tmp/boost -name "b2" -o -name "bjam"
    fi
    
    if [ -f "/tmp/boost/bin/bjam" ]; then
        echo "====> Found bjam at /tmp/boost/bin/bjam, creating symlinks"
        sudo ln -sf /tmp/boost/bin/bjam /opt/boost_${BOOST_VERSION_UNDERSCORED}/bjam
        sudo ln -sf /tmp/boost/bin/bjam /usr/local/bin/bjam
    else
        echo "WARNING: Could not find bjam at /tmp/boost/bin/bjam"
    fi
    
    # Copier les fichiers .jam dans le répertoire racine
    sudo cp -f /tmp/boost/share/boost-build/boost-build.jam /opt/boost_${BOOST_VERSION_UNDERSCORED}/
    sudo cp -f /tmp/boost/share/boost-build/project-config.jam /opt/boost_${BOOST_VERSION_UNDERSCORED}/
    
    # Exporter les variables nécessaires pour b2
    export BOOST_ROOT=/opt/boost_${BOOST_VERSION_UNDERSCORED}
    export BOOST_INCLUDEDIR=${BOOST_ROOT}
    export BOOST_BUILD_PATH=${BOOST_ROOT}
    
    echo "====> Boost configured for compatibility with external build scripts"
}

# -----------------------------------------------------------------------------
# 2) Télécharger et compiler libtorrent-rasterbar
# -----------------------------------------------------------------------------
build_libtorrent() {
    echo "====> Downloading and building libtorrent-rasterbar $LIBTORRENT_VERSION"
    
    local SRC_DIR="$BASE_DIR/libtorrent-$LIBTORRENT_VERSION"
    
    # Nettoyer les anciens fichiers
    echo "====> Cleaning any existing libtorrent directories"
    cd "$BASE_DIR"
    rm -rf libtorrent-*
    
    # Télécharger libtorrent-rasterbar
    echo "====> Downloading libtorrent-rasterbar"
    git clone --depth 1 --recursive --recurse-submodules --branch "v$LIBTORRENT_VERSION" "https://github.com/arvidn/libtorrent.git" "$SRC_DIR"
    
    cd "$SRC_DIR"
    
    # Afficher le commit actuel
    git --no-pager log -1 --oneline
    
    # Créer le fichier manquant deps/try_signal/try_signal.cpp
    echo "====> Creating missing dependency file try_signal.cpp"
    mkdir -p deps/try_signal
    cat > deps/try_signal/try_signal.cpp << 'EOF'
// Empty implementation file to satisfy CMake dependency
#include <csignal>
int main() { return 0; }
EOF
    
    # Installation des dépendances nécessaires
    echo "====> Installing build dependencies"
    sudo apt-get update
    sudo apt-get install -y build-essential libssl-dev cmake ninja-build
    
    # Variables pour la compilation
    export CFLAGS="-O3 -march=native"
    export CXXFLAGS="-O3 -march=native -std=c++17"
    # Construire avec CMake
    echo "====> Building libtorrent-rasterbar with CMake"
    
    # Créer le répertoire de build
    mkdir -p build
    cd build
    
    # Configuration avec CMake
    echo "====> Configuring libtorrent-rasterbar with CMake"
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$PREFIX \
        -DCMAKE_CXX_STANDARD=17 \
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -Dpython-bindings=OFF \
        -DCMAKE_PREFIX_PATH=/tmp/boost \
        -GNinja
    
    # Compiler la bibliothèque partagée
    echo "====> Building libtorrent-rasterbar shared library"
    ninja -j$CORES
    
    # Installer dans le répertoire temporaire
    echo "====> Installing libtorrent-rasterbar to $INSTALL_DIR"
    DESTDIR="$INSTALL_DIR" ninja install
    
    # Compiler la bibliothèque statique
    echo "====> Compiling static library"
    cd "$SRC_DIR"
    
    # Créer la bibliothèque statique à partir des objets
    echo "====> Creating static library from object files"
    OBJECTS_PATH=$(find build -name "*.o" -not -path "*/CMakeFiles/ShowIncludes/*" -not -path "*/examples/*" -not -path "*/tests/*" -not -path "*/tools/*")
    ar crs libtorrent-rasterbar.a $OBJECTS_PATH
    
    # Afficher des informations sur la bibliothèque statique
    echo "====> Static library information:"
    ls -la libtorrent-rasterbar.a
    
    # Copier manuellement le fichier .a dans le répertoire d'installation
    echo "====> Installing libtorrent-rasterbar.a to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR$PREFIX/lib"
    cp libtorrent-rasterbar.a "$INSTALL_DIR$PREFIX/lib/"
    
    # Ajuster le fichier .pc si nécessaire pour pointer vers /usr/local/lib
    if [ -f "$INSTALL_DIR/$PREFIX/lib/pkgconfig/libtorrent-rasterbar.pc" ]; then
        # S'assurer que libdir pointe vers le bon chemin
        sed -i "s|^libdir=.*|libdir=$PREFIX/lib|g" "$INSTALL_DIR/$PREFIX/lib/pkgconfig/libtorrent-rasterbar.pc"
    fi
    
    cd "$WHEREAMI"
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------
install_boost
build_libtorrent

echo "====> All done! libtorrent-rasterbar has been built."
echo "====> The library files are in $INSTALL_DIR$PREFIX/lib"
echo "====> The header files are in $INSTALL_DIR$PREFIX/include/libtorrent"
echo "====> You can now build Python bindings with build-bindings.sh"
exit 0 
