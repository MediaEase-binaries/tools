#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <libudns version> <build option>"
    exit 1
fi

LIBUDNS_VERSION="$1"
LIBUDNS_BUILD_OPTION="$2"
PKGNAME="libudns"
BASE_DIR="$PWD/custom_build"
INSTALL_DIR="$BASE_DIR/install"
SRC_DIR="$BASE_DIR/udns-${LIBUDNS_VERSION}"
TARFILE="$PWD/dist/${PKGNAME}/udns_${LIBUDNS_VERSION}.tar.gz"
FLTO=$(nproc)
if [ ! -f "$TARFILE" ]; then
    echo "Error: The file $TARFILE does not exist."
    exit 1
fi
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR/tmp"
tar -xzf "$TARFILE" -C "$SRC_DIR/tmp"
TOPDIR=$(ls "$SRC_DIR/tmp" | head -1)
mv "$SRC_DIR/tmp/$TOPDIR"/* "$SRC_DIR"
rm -rf "$SRC_DIR/tmp"
cd "$SRC_DIR"
export CFLAGS="-O1 -DNDEBUG -g0 -ffunction-sections -fdata-sections -w -flto=$FLTO -pipe"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--gc-sections -s"
./configure
make -j"$FLTO" CFLAGS="$CFLAGS" sharedlib dnsget rblcheck
mkdir -p "$INSTALL_DIR/usr/include"
mkdir -p "$INSTALL_DIR/usr/bin"
mkdir -p "$INSTALL_DIR/usr/lib/x86_64-linux-gnu"
cp -v udns.h "$INSTALL_DIR/usr/include/"
cp -v dnsget "$INSTALL_DIR/usr/bin/"
cp -v rblcheck "$INSTALL_DIR/usr/bin/"
cp -v libudns.so.0 "$INSTALL_DIR/usr/lib/x86_64-linux-gnu/"
cp -v libudns.a "$INSTALL_DIR/usr/lib/x86_64-linux-gnu/"
ln -sf libudns.so.0 "$INSTALL_DIR/usr/lib/x86_64-linux-gnu/libudns.so"
find "$INSTALL_DIR" -type f -exec file {} \; | grep ELF | cut -d: -f1 | xargs --no-run-if-empty strip --strip-unneeded
