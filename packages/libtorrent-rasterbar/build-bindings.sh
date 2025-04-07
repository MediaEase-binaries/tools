#!/usr/bin/env bash
set -e

# =============================================================================
# build-bindings.sh
#
# Ce script compile uniquement les bindings Python pour libtorrent-rasterbar
# (sans créer de package Debian)
#
# Usage:
# ./build-bindings.sh <VERSION>
# Exemple:
# ./build-bindings.sh 2.0.9
#
# Notes:
# - Nécessite que la bibliothèque libtorrent-rasterbar ait été compilée par build-lib.sh
# - Utilise b2 (Boost.Build) pour compiler les bindings Python
# - Installe dans le répertoire ./custom_build/install-python uniquement
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

echo "====> Building Python bindings for libtorrent-rasterbar $LIBTORRENT_VERSION (build: $BUILD)"
echo "====> Full version: $FULL_VERSION"

WHEREAMI="$(dirname "$(readlink -f "$0")")"
PREFIX="/usr/local"
BASE_DIR="$PWD/custom_build"
mkdir -p "$BASE_DIR"

# Répertoires d'installation
INSTALL_DIR="$BASE_DIR/install"           # Où la bibliothèque C++ a été installée
INSTALL_DIR_PYTHON="$BASE_DIR/install-python"
mkdir -p "$INSTALL_DIR_PYTHON"

# Nombre de cœurs pour compilation parallèle
CORES=$(nproc)

# Déterminer quelle version de Python utiliser
echo "====> Using system Python for libtorrent $LIBTORRENT_VERSION bindings"
PYTHON_EXECUTABLE=$(which python3)
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_MAJOR=$(python3 -c 'import sys; print(f"{sys.version_info.major}")')
PYTHON_MINOR=$(python3 -c 'import sys; print(f"{sys.version_info.minor}")')
PYTHON_INCLUDE=$(python3 -c 'import sysconfig; print(sysconfig.get_path("include"))')
PYTHON_LIB=$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("LIBDIR"))')

echo "====> Using Python version: $PYTHON_VERSION (major: $PYTHON_MAJOR, minor: $PYTHON_MINOR)"
echo "====> Python executable: $PYTHON_EXECUTABLE"
echo "====> Python include path: $PYTHON_INCLUDE"
echo "====> Python library path: $PYTHON_LIB"

# Déterminer quelle version de Boost utiliser
# find boost-mediaease package in the tools/ directory
BOOST_PACKAGE_NAME=$(find "$WHEREAMI/tools/" -name "boost-mediaease_*.deb")
BOOST_VERSION=$(echo "$BOOST_PACKAGE_NAME" | sed -n 's/.*boost-mediaease_\(.*\)_amd64\.deb/\1/p')
BOOST_VERSION_UNDERSCORED=$(echo "$BOOST_VERSION" | sed 's/\./_/g')

# -----------------------------------------------------------------------------
# 1) Vérifier si les prérequis sont installés
# -----------------------------------------------------------------------------
check_prerequisites() {
    echo "====> Checking prerequisites"

    # Vérifier si libtorrent-rasterbar a été compilé
    if [ ! -d "$INSTALL_DIR$PREFIX/include/libtorrent" ] || [ ! -f "$INSTALL_DIR$PREFIX/lib/libtorrent-rasterbar.so" ]; then
        echo "ERROR: libtorrent-rasterbar has not been built yet!"
        echo "Please run ./build-lib.sh $LIBTORRENT_VERSION first"
        exit 1
    fi

    # Vérifier que le package boost-mediaease de la bonne version est installé
    if ! dpkg -l | grep -q "boost-mediaease" || ! dpkg -l | grep "boost-mediaease" | grep -q "$BOOST_VERSION"; then
        echo "ERROR: boost-mediaease $BOOST_VERSION is not installed!"
        echo "Please run ./build-lib.sh $LIBTORRENT_VERSION first"
        exit 1
    fi

    if [ ! -f "$INSTALL_DIR$PREFIX/include/libtorrent/torrent_handle.hpp" ] || [ ! -f "$INSTALL_DIR$PREFIX/lib/libtorrent-rasterbar.so" ]; then
        echo "ERROR: libtorrent-rasterbar files not found in $INSTALL_DIR$PREFIX."
        echo "Make sure you have run build-lib.sh first to compile the library."
        exit 1
    fi
    
    # Vérifier que Python et les dépendances sont installées
    echo "====> Checking Python dependencies"
    sudo apt-get update
    sudo apt-get install -y python3-dev python3-setuptools

    echo "====> All prerequisites satisfied"
}

# -----------------------------------------------------------------------------
# 3) Télécharger les sources libtorrent si nécessaire
# -----------------------------------------------------------------------------
check_sources() {
    echo "====> Checking libtorrent-rasterbar sources for Python bindings"
    
    local SRC_DIR="$BASE_DIR/libtorrent-$LIBTORRENT_VERSION"
    
    # Vérifier si les sources existent déjà
    if [ -d "$SRC_DIR" ]; then
        echo "====> Sources directory already exists, using existing one"
    else
        echo "ERROR: Source directory $SRC_DIR not found."
        echo "Please run build-lib.sh first to download and compile the library."
        exit 1
    fi
    
    cd "$WHEREAMI"
}

# Fonction pour compiler les bindings Python avec b2 uniquement
compile_with_b2() {
    local SRC_DIR="$1"
    local INSTALL_DIR="$2"
    local PREFIX="$3"
    local PYTHON_VERSION="$4"
    local PYTHON_EXECUTABLE="$5"
    local PYTHON_MAJOR="$6"
    local PYTHON_MINOR="$7"
    
    echo "====> Building Python bindings with b2"
    
    # Aller dans le répertoire des bindings Python
    cd "$SRC_DIR/bindings/python"
    
    # Nettoyer les anciens fichiers build
    rm -rf build
    
    # Chercher b2 dans les emplacements standard
    local B2_PATH=""
    for b2_location in "/tmp/boost/bin/b2" "/opt/boost_${BOOST_VERSION_UNDERSCORED}/b2" "/usr/local/bin/b2"; do
        if [ -x "$b2_location" ]; then
            B2_PATH="$b2_location"
            break
        fi
    done
    
    if [ -z "$B2_PATH" ]; then
        echo "ERROR: b2 executable not found in standard locations"
        echo "Checked: /tmp/boost/bin/b2, /opt/boost_${BOOST_VERSION_UNDERSCORED}/b2, /usr/local/bin/b2"
        exit 1
    fi
    
    echo "====> Using b2 at: $B2_PATH"
    
    # Variables pour la compilation
    local CRYPTO="openssl"
    local DEST_DIR="$INSTALL_DIR$PREFIX/lib/python$PYTHON_VERSION/dist-packages"
    
    # S'assurer que le répertoire de destination existe
    mkdir -p "$DEST_DIR"
    
    # Création d'un fichier project-config.jam temporaire
    echo "====> Creating temporary project-config.jam"
    cat > project-config.jam << EOF
# Boost.Build Configuration
using python 
  : $PYTHON_VERSION
  : $PYTHON_EXECUTABLE
  : $PYTHON_INCLUDE
  : $PYTHON_LIB
  ;
EOF
    
    # Afficher les commandes avant de les exécuter pour le débogage
    echo "====> Running b2 command:"
    echo "$B2_PATH -j$CORES python=$PYTHON_MAJOR crypto=$CRYPTO variant=release libtorrent-link=static boost-link=static include=$INSTALL_DIR$PREFIX/include library-path=$INSTALL_DIR$PREFIX/lib install_module python-install-path=$DEST_DIR"
    
    # Exécuter b2 pour construire les bindings Python
    $B2_PATH -j$CORES \
        python=$PYTHON_MAJOR \
        crypto=$CRYPTO \
        variant=release \
        libtorrent-link=static \
        boost-link=static \
        include="$INSTALL_DIR$PREFIX/include" \
        library-path="$INSTALL_DIR$PREFIX/lib" \
        install_module \
        python-install-path="$DEST_DIR"
    
    # Vérifier si la compilation a réussi
    if [ $? -ne 0 ]; then
        echo "ERROR: b2 command failed to build the Python bindings"
        return 1
    fi
    
    # Vérifier si le module a été correctement installé
    if [ -f "$DEST_DIR/libtorrent.so" ]; then
        echo "====> Python bindings successfully built and installed"
        return 0
    else
        echo "ERROR: libtorrent.so not found in $DEST_DIR after building"
        echo "====> Searching for libtorrent.so in the build directory:"
        find . -name "libtorrent*.so" -exec ls -la {} \;
        
        # Si b2 a généré le fichier ailleurs, essayer de le copier manuellement
        local FOUND_MODULE=$(find . -name "libtorrent*.so" | head -n 1)
        if [ -n "$FOUND_MODULE" ]; then
            echo "====> Found module at $FOUND_MODULE, copying manually"
            cp -fv "$FOUND_MODULE" "$DEST_DIR/libtorrent.so"
            if [ -f "$DEST_DIR/libtorrent.so" ]; then
                echo "====> Manual copy successful"
                return 0
            fi
        fi
        
        return 1
    fi
}

# -----------------------------------------------------------------------------
# 4) Compiler les bindings Python
# -----------------------------------------------------------------------------
build_python_bindings() {
    echo "====> Building Python bindings"
    
    local SRC_DIR="$BASE_DIR/libtorrent-$LIBTORRENT_VERSION"
    
    # S'assurer que libtorrent-rasterbar est accessible
    export LD_LIBRARY_PATH="$INSTALL_DIR$PREFIX/lib:$LD_LIBRARY_PATH"
    
    # Compiler avec b2
    if compile_with_b2 "$SRC_DIR" "$INSTALL_DIR" "$PREFIX" "$PYTHON_VERSION" "$PYTHON_EXECUTABLE" "$PYTHON_MAJOR" "$PYTHON_MINOR"; then
        echo "====> b2 build successful"
    else
        echo "ERROR: Failed to build Python bindings with b2"
        exit 1
    fi
    
    # Vérifier le résultat final
    if [ -f "$INSTALL_DIR$PREFIX/lib/python$PYTHON_VERSION/dist-packages/libtorrent.so" ]; then
        echo "====> Python bindings successfully built"
        file "$INSTALL_DIR$PREFIX/lib/python$PYTHON_VERSION/dist-packages/libtorrent.so"
    else
        echo "ERROR: Python bindings not found in the expected location"
        exit 1
    fi
    
    cd "$WHEREAMI"
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------
check_prerequisites
check_sources
build_python_bindings

echo "====> All done! Python bindings have been built."
echo "====> The Python bindings are in $INSTALL_DIR$PREFIX/lib/python$PYTHON_VERSION/dist-packages/libtorrent.so"
echo "====> You can now create packages with build-packages.sh"
exit 0 
