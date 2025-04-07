#!/usr/bin/env bash
set -e

# =============================================================================
# build.sh
#
# Ce script compile Deluge en statique en mode ligne de commande
# pour une utilisation sur serveur dédié
#
# Usage:
# ./build.sh <VERSION>
# Exemple:
# ./build.sh 2.1.1
#
# Notes:
# - Versions supportées:
#   - 2.0.5 - oldstable
#   - 2.1.1 - stable 
#   - 2.2.0 - next (development version)
# =============================================================================

usage() {
    echo "Usage: $0 <VERSION>"
    echo "Example: $0 2.1.1"
    echo "Supported versions: 2.0.5, 2.1.1, 2.2.0"
    exit 1
}

# Analyser les arguments
if [ $# -ne 1 ]; then
    usage
fi

INPUT_VERSION="$1"

# -----------------------------------------------------------------------------
# 0) Paramètres et variables globales
# -----------------------------------------------------------------------------
DELUGE_VERSION="${INPUT_VERSION}"
BUILD="1build1"
FULL_VERSION="${DELUGE_VERSION}-${BUILD}"
CREATE_DEB="true"  # Activer la création de paquets Debian par défaut

# Déterminer la stabilité et le tag git
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

# Répertoires d'installation
INSTALL_DIR="$BASE_DIR/install"
mkdir -p "$INSTALL_DIR"

# Architecture
ARCHITECTURE=$(dpkg --print-architecture)

# Nombre de cœurs pour compilation parallèle
CORES=$(nproc)

# Python version
PYTHON_VERSION="3"
PYTHON_CMD="python3"

# -----------------------------------------------------------------------------
# 1) Installer les dépendances de base
# -----------------------------------------------------------------------------
install_dependencies() {
    echo "====> Installing required dependencies"
    
    sudo apt-get update
    sudo apt-get install -y build-essential cmake pkg-config libssl-dev \
                          zlib1g-dev libgeoip-dev ${PYTHON_CMD} \
                          ${PYTHON_CMD}-dev ${PYTHON_CMD}-pip \
                          ${PYTHON_CMD}-setuptools ${PYTHON_CMD}-wheel

    # Installer les dépendances Python
    ${PYTHON_CMD} -m pip install --upgrade pip
    ${PYTHON_CMD} -m pip install twisted pyopenssl service_identity pillow \
                         rencode pyxdg chardet setproctitle setuptools wheel
}

# -----------------------------------------------------------------------------
# 2) Installer libtorrent-rasterbar depuis le dépôt
# -----------------------------------------------------------------------------
install_libtorrent() {
    echo "====> Installing libtorrent-rasterbar $LIBTORRENT_VERSION from MediaEase repository"
    
    # Nom du package libtorrent
    local LIBTORRENT_PACKAGE_NAME="libtorrent-rasterbar-mediaease_${LIBTORRENT_VERSION}-1build1_amd64.deb"
    
    # Vérifier si le package est déjà installé
    if dpkg -l | grep -q "libtorrent-rasterbar-mediaease" && dpkg -l | grep "libtorrent-rasterbar-mediaease" | grep -q "$LIBTORRENT_VERSION"; then
        echo "====> libtorrent-rasterbar-mediaease $LIBTORRENT_VERSION is already installed"
    else
        echo "====> Installing libtorrent-rasterbar-mediaease $LIBTORRENT_VERSION from tools directory"
        
        # Chercher le package libtorrent avec le nom exact
        local LIBTORRENT_PACKAGE="$WHEREAMI/tools/$LIBTORRENT_PACKAGE_NAME"
        
        if [ ! -f "$LIBTORRENT_PACKAGE" ]; then
            echo "ERROR: $LIBTORRENT_PACKAGE_NAME not found in the tools directory!"
            echo "Please download the libtorrent-rasterbar-mediaease package and place it in the tools directory."
            exit 1
        fi
        
        echo "====> Found libtorrent package: $LIBTORRENT_PACKAGE"
        sudo dpkg -i "$LIBTORRENT_PACKAGE"
    fi
    
    # Vérifier que libtorrent a été correctement installé
    if ! pkg-config --exists libtorrent-rasterbar; then
        echo "ERROR: libtorrent-rasterbar not found with pkg-config!"
        echo "The libtorrent package might not be installed correctly or pkg-config files are missing."
        exit 1
    fi
    
    # Installer les bindings Python pour libtorrent
    echo "====> Installing Python bindings for libtorrent-rasterbar"
    ${PYTHON_CMD} -m pip install --upgrade python-libtorrent
    
    echo "====> libtorrent-rasterbar configuration completed"
}

# -----------------------------------------------------------------------------
# 3) Télécharger et compiler Deluge
# -----------------------------------------------------------------------------
build_deluge() {
    echo "====> Downloading and building Deluge $DELUGE_VERSION"
    
    local SRC_DIR="$BASE_DIR/deluge-$DELUGE_VERSION"
    
    # Nettoyer les anciens fichiers
    echo "====> Cleaning any existing Deluge directories"
    cd "$BASE_DIR"
    rm -rf deluge-*
    
    # Télécharger Deluge
    echo "====> Downloading Deluge"
    git clone --depth 1 --branch "$TAG" "https://github.com/deluge-torrent/deluge.git" "$SRC_DIR"
    
    cd "$SRC_DIR"
    
    # Afficher le commit actuel
    git --no-pager log -1 --oneline
    
    # Installer Deluge en mode développement dans notre environnement
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
    
    # Vérifier que les exécutables ont été compilés correctement
    if [ ! -f "$INSTALL_DIR$PREFIX/bin/deluged" ] || [ ! -f "$INSTALL_DIR$PREFIX/bin/deluge-web" ]; then
        echo "ERROR: Deluge executables not found at $INSTALL_DIR$PREFIX/bin/deluged or $INSTALL_DIR$PREFIX/bin/deluge-web"
        echo "Compilation might have failed."
        exit 1
    fi
    
    # Afficher les informations sur les exécutables
    echo "====> Deluge executables information:"
    file "$INSTALL_DIR$PREFIX/bin/deluged"
    file "$INSTALL_DIR$PREFIX/bin/deluge-web"
    
    # Copier les exécutables dans le répertoire de sortie
    echo "====> Copying Deluge executables to output directory"
    mkdir -p "$WHEREAMI/output"
    
    # Copier tous les exécutables
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
    
    # Création du package Debian
    if [ -n "$CREATE_DEB" ] && [ "$CREATE_DEB" = "true" ]; then
        echo "====> Creating Debian package"
        local PKG_DIR="$BASE_DIR/deb-pkg"
        local PACKAGE_NAME="deluge-${STABILITY}_${DELUGE_VERSION}-${BUILD}_${ARCHITECTURE}.deb"
        
        # Nettoyer l'ancien répertoire de packaging
        rm -rf "$PKG_DIR"
        
        # Créer les répertoires nécessaires pour le paquet Debian
        mkdir -p "$PKG_DIR/DEBIAN"
        
        # Chemin d'installation dans /opt
        local INSTALL_PATH="/opt/MediaEase/.binaries/installed/deluge-${STABILITY}_${DELUGE_VERSION}"
        mkdir -p "$PKG_DIR/$INSTALL_PATH"
        
        # Copier l'arborescence d'installation
        cp -r "$INSTALL_DIR$PREFIX" "$PKG_DIR/$INSTALL_PATH/"
        
        # Nettoyer les binaires (strip)
        find "$PKG_DIR" -type f -exec file {} \; | grep ELF | cut -d: -f1 | xargs --no-run-if-empty strip --strip-unneeded
        
        # Calculer la taille installée (en KB)
        local INSTALLED_SIZE=$(du -sk "$PKG_DIR/opt" | cut -f1)
        
        # Créer le fichier control avec les dépendances minimales
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

        # Créer le fichier postinst
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
        
        # Définir la priorité en fonction de la stabilité
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
        
        # Créer le fichier d'environnement
        cat > "${ENV_FILE}" <<EOF2
export PATH="${INSTALL_USR}/bin:\$PATH"
export PYTHONPATH="${INSTALL_USR}/lib/python3/dist-packages:\$PYTHONPATH"
EOF2
        
        # Mettre à jour les alternatives pour les binaires
        for bin in deluged deluge-web deluge-console deluge-gtk; do
            if [ -f "${INSTALL_USR}/bin/${bin}" ]; then
                update-alternatives --install "/usr/bin/${bin}" "${bin}" "${INSTALL_USR}/bin/${bin}" ${PRIORITY}
            fi
        done
        
        # Mettre à jour la base de données des pages de manuel si disponible
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

        # Créer le fichier prerm
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

        # Générer le fichier md5sums
        echo "Generating md5sums..."
        (
            cd "$PKG_DIR"
            find . -type f ! -path "./DEBIAN/*" -exec md5sum {} \; > DEBIAN/md5sums
        )

        # Rendre les scripts exécutables
        chmod 755 "$PKG_DIR/DEBIAN/postinst" "$PKG_DIR/DEBIAN/prerm"
        
        # Créer le package
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
