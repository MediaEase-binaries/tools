#!/usr/bin/env bash
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/install-dir"
    exit 1
fi

DESTDIR="$1"
FLTO=$(nproc)

export CFLAGS="-Os -DNDEBUG -g0 -ffunction-sections -fdata-sections"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--gc-sections -s"
./configure --prefix=/usr
make -j"$FLTO"
make install DESTDIR="$DESTDIR"
