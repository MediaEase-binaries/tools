#!/usr/bin/env bash
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <xmlrpc-c version>"
    exit 1
fi

XMLRPC_VERSION="$1"
PKGNAME="xmlrpc-c"
BASE_DIR="$PWD/custom_build"
INSTALL_DIR="$BASE_DIR/install"
SRC_DIR="$BASE_DIR/${PKGNAME}-${XMLRPC_VERSION}"
ZIPFILE="$PWD/dist/${PKGNAME}/${PKGNAME}-${XMLRPC_VERSION}.zip"
FLTO=$(nproc)
if [ ! -f "$ZIPFILE" ]; then
    echo "Error: The file $ZIPFILE does not exist."
    exit 1
fi
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"
unzip "$ZIPFILE" -d "$SRC_DIR/tmp"
TOPDIR=$(ls "$SRC_DIR/tmp" | head -1)
mv "$SRC_DIR/tmp/$TOPDIR"/* "$SRC_DIR"
rm -rf "$SRC_DIR/tmp"
cd "$SRC_DIR"
export CFLAGS="-Os -DNDEBUG -g0 -ffunction-sections -fdata-sections"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--gc-sections -s"
./configure --prefix=/usr
make -j"$FLTO"
make install DESTDIR="$INSTALL_DIR"
find "$INSTALL_DIR" -type f -exec file {} \; | grep ELF | cut -d: -f1 | xargs --no-run-if-empty strip --strip-unneeded
