#!/usr/bin/env bash
set -e

# =============================================================================
# build-lib.sh
#
# This script compiles the libtorrent-rasterbar library
#
# Usage:
# ./build-lib.sh <DESTDIR>
# =============================================================================

if [ $# -ne 1 ]; then
    echo "Usage: $0 <DESTDIR>"
    echo "Example: $0 /path/to/install/dir"
    exit 1
fi
DESTDIR="$1"
PREFIX="/usr/local"
CORES=$(nproc)
if [ -z "$SRC_DIR" ]; then
    SRC_DIR="$PWD/libtorrent"
fi
if [ ! -d "$SRC_DIR" ]; then
    echo "ERROR: Source directory $SRC_DIR does not exist"
    exit 1
fi
PYTHON_VERSION=$(python3 --version | awk '{print $2}')
PYTHON_VERSION_SHORT=$(echo "$PYTHON_VERSION" | cut -d. -f1-2)
PYTHON_VERSION_NO_DOTS=$(echo "$PYTHON_VERSION" | sed 's/\.//g' | cut -c1-3)
PYTHON_LIBRARY="/usr/lib/x86_64-linux-gnu/libpython${PYTHON_VERSION_SHORT}.so"
echo "====> Building libtorrent-rasterbar"
echo "====> Source directory: $SRC_DIR"
echo "====> Python: version=$PYTHON_VERSION, short=$PYTHON_VERSION_SHORT, no_dots=$PYTHON_VERSION_NO_DOTS"
echo "====> Installing build dependencies"
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev cmake ninja-build python3-dev
if [ ! -f "$PYTHON_LIBRARY" ]; then
    echo "Could not find Python library at $PYTHON_LIBRARY"
    PYTHON_LIBRARY=$(find /usr/lib -name "libpython${PYTHON_VERSION_SHORT}*.so*" | head -1)
    echo "Found Python library at $PYTHON_LIBRARY"
fi
export CFLAGS="-O3 -march=native"
export CXXFLAGS="-O3 -march=native -std=c++17"
echo "====> Building libtorrent-rasterbar with CMake"
cd "$SRC_DIR"
mkdir -p build
cd build
echo "====> Configuring libtorrent-rasterbar with CMake"
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_CXX_STANDARD=17 \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -Dpython-bindings=ON \
    -Dpython-egg-info=ON \
    -DBOOST_ROOT="$PREFIX" \
    -DBOOST_INCLUDEDIR="$PREFIX/include" \
    -DBOOST_LIBRARYDIR="$PREFIX/lib" \
    -GNinja
echo "====> Building libtorrent-rasterbar shared library"
ninja -j$CORES
echo "====> Installing libtorrent-rasterbar into staging area ($DESTDIR)"
mkdir -p "$DESTDIR"
DESTDIR="$DESTDIR" ninja install
echo "====> Creating static library from object files"
cd "$SRC_DIR"
OBJECTS_PATH=$(find build -name "*.o" -not -path "*/CMakeFiles/ShowIncludes/*" -not -path "*/examples/*" -not -path "*/tests/*" -not -path "*/tools/*")
ar crs libtorrent-rasterbar.a $OBJECTS_PATH
echo "====> Static library information:"
ls -la libtorrent-rasterbar.a
echo "====> Installing libtorrent-rasterbar.a to $DESTDIR"
mkdir -p "$DESTDIR$PREFIX/lib"
cp libtorrent-rasterbar.a "$DESTDIR$PREFIX/lib/"
if [ -f "$DESTDIR/$PREFIX/lib/pkgconfig/libtorrent-rasterbar.pc" ]; then
    sed -i "s|^libdir=.*|libdir=$PREFIX/lib|g" "$DESTDIR/$PREFIX/lib/pkgconfig/libtorrent-rasterbar.pc"
fi
SOURCE_DIR="$DESTDIR$PREFIX"
TARGET_DESTDIR="$DESTDIR"
echo "====> Relocating files for packaging"
mkdir -p "$TARGET_DESTDIR/pkg_runtime/usr/lib/x86_64-linux-gnu"
mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu"
mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/include"
mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar"
mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/pkgconfig"
mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/share/cmake/Modules"
mkdir -p "$TARGET_DESTDIR/pkg_python/usr/lib/python3/dist-packages"
echo "====> Checking installed files in $SOURCE_DIR"
find "$SOURCE_DIR" -type f -name "*libtorrent*" | sort
echo "====> Copying shared libraries for runtime package"
LIB_PATTERN="libtorrent-rasterbar.so.2.0.*"
SO_FILES=$(find "$SRC_DIR" -type f -name "$LIB_PATTERN")
SOLINK_FILES=$(find "$SRC_DIR" -type l -name "libtorrent-rasterbar.so.2.0")
if [ -n "$SO_FILES" ]; then
    echo "Found shared library files:"
    echo "$SO_FILES"
    echo "$SOLINK_FILES"
    MAIN_SO=$(echo "$SO_FILES" | head -1)
    MAIN_SO_DIR=$(dirname "$MAIN_SO")
    echo "Copying from $MAIN_SO_DIR"
    for SO_FILE in $SO_FILES; do
        cp -P "$SO_FILE" "$TARGET_DESTDIR/pkg_runtime/usr/lib/x86_64-linux-gnu/"
    done
    for SOLINK in $SOLINK_FILES; do
        cp -P "$SOLINK" "$TARGET_DESTDIR/pkg_runtime/usr/lib/x86_64-linux-gnu/"
    done
    cd "$TARGET_DESTDIR/pkg_runtime/usr/lib/x86_64-linux-gnu/"
    SO_VERSION=$(ls libtorrent-rasterbar.so.2.0.* | sort | head -1)
    if [ -n "$SO_VERSION" ] && [ ! -L "libtorrent-rasterbar.so.2.0" ]; then
        ln -sf "$SO_VERSION" "libtorrent-rasterbar.so.2.0"
    fi
    cd - > /dev/null
else
    echo "ERROR: Could not find any libtorrent-rasterbar.so files anywhere!"
    echo "Searched with pattern: $LIB_PATTERN"
    echo "Directories searched:"
    find "$SRC_DIR" -type d | grep -v CMakeFiles | sort
    find "." -type f -name "libtorrent-rasterbar.so*"
    exit 1
fi
if [ -d "$SOURCE_DIR/include/libtorrent" ]; then
    echo "Copying include files from $SOURCE_DIR/include/"
    cp -r "$SOURCE_DIR/include/libtorrent" "$TARGET_DESTDIR/pkg_dev/usr/include/"
else
    echo "WARNING: Include directory not found at $SOURCE_DIR/include/libtorrent"
    FOUND_INCLUDE=$(find "$SRC_DIR/build" -type d -name "libtorrent" -path "*/include/*" | head -1)
    if [ -n "$FOUND_INCLUDE" ]; then
        echo "Found include directory: $FOUND_INCLUDE"
        cp -r "$FOUND_INCLUDE" "$TARGET_DESTDIR/pkg_dev/usr/include/"
    else
        FOUND_INCLUDE=$(find "$SRC_DIR/include" -type d -name "libtorrent" 2>/dev/null | head -1)
        if [ -n "$FOUND_INCLUDE" ]; then
            echo "Found include directory in source: $FOUND_INCLUDE"
            cp -r "$FOUND_INCLUDE" "$TARGET_DESTDIR/pkg_dev/usr/include/"
        else
            echo "ERROR: Could not find libtorrent include directory!"
            exit 1
        fi
    fi
fi
SODEV_FILES=$(find "$SRC_DIR" -name "libtorrent-rasterbar.so" | head -1)
if [ -n "$SODEV_FILES" ]; then
    SODEV="$SODEV_FILES"
    echo "Copying dev library from $(dirname "$SODEV")"
    cp "$SODEV" "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/"
    
    cd "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/"
    if [ -f "libtorrent-rasterbar.so" ] && [ ! -L "libtorrent-rasterbar.so" ]; then
        # mv "libtorrent-rasterbar.so" "libtorrent-rasterbar.so.orig"
        ln -sf "libtorrent-rasterbar.so.2.0" "libtorrent-rasterbar.so"
    fi
    cd - > /dev/null
fi

# Replace the existing CMake files section with this improved version
if [ -d "$SOURCE_DIR/lib/cmake/LibtorrentRasterbar" ]; then
    echo "✓ Found CMake files at $SOURCE_DIR/lib/cmake/LibtorrentRasterbar"
    echo "Contents of this directory:"
    ls -la "$SOURCE_DIR/lib/cmake/LibtorrentRasterbar/"
    echo "Copying cmake files from $SOURCE_DIR/lib/cmake/"
    mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar"
    cp -r "$SOURCE_DIR/lib/cmake/LibtorrentRasterbar/"* "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar/"
else
    echo "✗ CMake files not found at $SOURCE_DIR/lib/cmake/LibtorrentRasterbar"
    
    # Look in the build directory directly first
    echo "Checking in build directory for CMake files..."
    BUILD_CMAKE_DIR="$SRC_DIR/build/LibtorrentRasterbar"
    if [ -d "$BUILD_CMAKE_DIR" ] && [ -f "$BUILD_CMAKE_DIR/LibtorrentRasterbarConfig.cmake" ]; then
        echo "Found CMake files in the build directory at $BUILD_CMAKE_DIR"
        mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar"
        cp -v "$BUILD_CMAKE_DIR"/*.cmake "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar/"
        
        # Also check for release files
        RELEASE_CMAKE="$SRC_DIR/build/CMakeFiles/Export/3120ee627214a64104748d2207948443/LibtorrentRasterbarTargets-release.cmake"
        if [ -f "$RELEASE_CMAKE" ]; then
            echo "Found release CMake file: $RELEASE_CMAKE"
            cp -v "$RELEASE_CMAKE" "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar/"
        fi
    else
        # Fallback to searching more broadly
        echo "Searching for CMake files in build directory..."
        FOUND_CMAKE_FILES=$(find "$SRC_DIR" -name "LibtorrentRasterbar*.cmake" 2>/dev/null | sort)
        
        if [ -n "$FOUND_CMAKE_FILES" ]; then
            echo "Found these CMake files:"
            echo "$FOUND_CMAKE_FILES"
            
            # Get the directory of the first config file found
            CONFIG_FILE=$(echo "$FOUND_CMAKE_FILES" | grep "Config.cmake" | head -1)
            if [ -n "$CONFIG_FILE" ]; then
                CONFIG_DIR=$(dirname "$CONFIG_FILE")
                echo "Using CMake files from: $CONFIG_DIR"
                
                mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar"
                cp -v "$CONFIG_DIR"/*.cmake "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar/" 2>/dev/null || true
            else
                # Generate minimal CMake config files
                LIBTORRENT_VERSION="2.0.0"
                
                # Try to get version from .so file
                SO_VERSION_FILE=$(find "$TARGET_DESTDIR" -name "libtorrent-rasterbar.so.*.*" | head -1)
                if [ -n "$SO_VERSION_FILE" ]; then
                    LIBTORRENT_VERSION=$(basename "$SO_VERSION_FILE" | sed 's/libtorrent-rasterbar.so.//')
                    echo "Detected version from .so file: $LIBTORRENT_VERSION"
                fi
                
                echo "Creating minimal CMake configuration files with version $LIBTORRENT_VERSION"
                mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar"
                
                cat > "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar/LibtorrentRasterbarConfig.cmake" <<EOF
# Generated manually by the build script
set(LIBTORRENT_RASTERBAR_VERSION ${LIBTORRENT_VERSION})
set(LIBTORRENT_RASTERBAR_INCLUDE_DIRS "/usr/include")

if(NOT TARGET LibtorrentRasterbar::torrent-rasterbar)
  add_library(LibtorrentRasterbar::torrent-rasterbar SHARED IMPORTED)
  set_target_properties(LibtorrentRasterbar::torrent-rasterbar PROPERTIES
    IMPORTED_LOCATION "/usr/lib/x86_64-linux-gnu/libtorrent-rasterbar.so.2.0"
    INTERFACE_INCLUDE_DIRECTORIES "/usr/include"
  )
endif()
EOF
                
                cat > "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar/LibtorrentRasterbarConfigVersion.cmake" <<EOF
# Generated manually by the build script
set(PACKAGE_VERSION "${LIBTORRENT_VERSION}")
if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
  endif()
endif()
EOF
                
                echo "Created minimal CMake configuration files"
            fi
        else
            # Last resort - always create the minimal files
            echo "No LibtorrentRasterbar*.cmake files found, creating minimal configuration"
            mkdir -p "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar"
            
            cat > "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar/LibtorrentRasterbarConfig.cmake" <<EOF
# Generated manually by the build script
set(LIBTORRENT_RASTERBAR_VERSION 2.0.0)
set(LIBTORRENT_RASTERBAR_INCLUDE_DIRS "/usr/include")

if(NOT TARGET LibtorrentRasterbar::torrent-rasterbar)
  add_library(LibtorrentRasterbar::torrent-rasterbar SHARED IMPORTED)
  set_target_properties(LibtorrentRasterbar::torrent-rasterbar PROPERTIES
    IMPORTED_LOCATION "/usr/lib/x86_64-linux-gnu/libtorrent-rasterbar.so.2.0"
    INTERFACE_INCLUDE_DIRECTORIES "/usr/include"
  )
endif()
EOF
            
            cat > "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/cmake/LibtorrentRasterbar/LibtorrentRasterbarConfigVersion.cmake" <<EOF
# Generated manually by the build script
set(PACKAGE_VERSION "2.0.0")
if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
  endif()
endif()
EOF
        fi
    fi
fi

if [ -f "$SOURCE_DIR/lib/pkgconfig/libtorrent-rasterbar.pc" ]; then
    echo "Copying pkgconfig file from $SOURCE_DIR/lib/pkgconfig/"
    cp "$SOURCE_DIR/lib/pkgconfig/libtorrent-rasterbar.pc" "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/pkgconfig/"
    sed -i "s|$PREFIX|/usr|g" "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/pkgconfig/libtorrent-rasterbar.pc"
    sed -i "s|libdir=/usr/lib|libdir=/usr/lib/x86_64-linux-gnu|g" "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/pkgconfig/libtorrent-rasterbar.pc"
else
    echo "WARNING: pkg-config file not found at $SOURCE_DIR/lib/pkgconfig/libtorrent-rasterbar.pc"
    FOUND_PC=$(find "$SRC_DIR" -name "libtorrent-rasterbar.pc" | head -1)
    if [ -n "$FOUND_PC" ]; then
        echo "Found pkg-config file: $FOUND_PC"
        cp "$FOUND_PC" "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/pkgconfig/"
        sed -i "s|$PREFIX|/usr|g" "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/pkgconfig/libtorrent-rasterbar.pc"
        sed -i "s|libdir=/usr/lib|libdir=/usr/lib/x86_64-linux-gnu|g" "$TARGET_DESTDIR/pkg_dev/usr/lib/x86_64-linux-gnu/pkgconfig/libtorrent-rasterbar.pc"
    fi
fi
if [ -f "$SOURCE_DIR/share/cmake/Modules/FindLibtorrentRasterbar.cmake" ]; then
    echo "Copying FindLibtorrentRasterbar.cmake from $SOURCE_DIR/share/cmake/Modules/"
    cp "$SOURCE_DIR/share/cmake/Modules/FindLibtorrentRasterbar.cmake" "$TARGET_DESTDIR/pkg_dev/usr/share/cmake/Modules/"
else
    echo "WARNING: FindLibtorrentRasterbar.cmake not found at $SOURCE_DIR/share/cmake/Modules/"
    FOUND_FIND=$(find "$SRC_DIR" -name "FindLibtorrentRasterbar.cmake" | head -1)
    if [ -n "$FOUND_FIND" ]; then
        echo "Found FindLibtorrentRasterbar.cmake: $FOUND_FIND"
        cp "$FOUND_FIND" "$TARGET_DESTDIR/pkg_dev/usr/share/cmake/Modules/"
    fi
fi
if ls "$SOURCE_DIR/lib/python3/dist-packages/libtorrent"*.so 2>/dev/null; then
    echo "Copying Python bindings from $SOURCE_DIR/lib/python3/dist-packages/"
    cp "$SOURCE_DIR/lib/python3/dist-packages/libtorrent"*.so "$TARGET_DESTDIR/pkg_python/usr/lib/python3/dist-packages/"
else
    echo "WARNING: Python bindings not found at $SOURCE_DIR/lib/python3/dist-packages/"
    FOUND_PY=$(find "$SRC_DIR" -name "libtorrent*.so" -path "*/python3/*" | head -1)
    if [ -n "$FOUND_PY" ]; then
        echo "Found Python bindings: $FOUND_PY"
        cp "$FOUND_PY" "$TARGET_DESTDIR/pkg_python/usr/lib/python3/dist-packages/"
    fi
fi
if [ -d "$SOURCE_DIR/lib/python3/dist-packages/libtorrent.egg-info" ]; then
    echo "Copying Python egg-info from $SOURCE_DIR/lib/python3/dist-packages/"
    cp -r "$SOURCE_DIR/lib/python3/dist-packages/libtorrent.egg-info" "$TARGET_DESTDIR/pkg_python/usr/lib/python3/dist-packages/"
else
    echo "WARNING: Python egg-info not found at $SOURCE_DIR/lib/python3/dist-packages/libtorrent.egg-info"
    FOUND_EGG=$(find "$SRC_DIR" -type d -name "libtorrent.egg-info" | head -1)
    if [ -n "$FOUND_EGG" ]; then
        echo "Found Python egg-info: $FOUND_EGG"
        cp -r "$FOUND_EGG" "$TARGET_DESTDIR/pkg_python/usr/lib/python3/dist-packages/"
    fi
fi
find "$TARGET_DESTDIR" -name "*.a" -delete
find "$TARGET_DESTDIR" -type f -exec file {} \; | grep ELF | cut -d: -f1 | xargs --no-run-if-empty strip --strip-unneeded
echo "====> Cleaning runtime package directory"
rm -rf "$TARGET_DESTDIR/pkg_runtime/usr/lib/x86_64-linux-gnu/cmake" 2>/dev/null || true
rm -rf "$TARGET_DESTDIR/pkg_runtime/usr/lib/x86_64-linux-gnu/pkgconfig" 2>/dev/null || true
rm -rf "$TARGET_DESTDIR/pkg_runtime/usr/lib/x86_64-linux-gnu/python3" 2>/dev/null || true
rm -f "$TARGET_DESTDIR/pkg_runtime/usr/lib/x86_64-linux-gnu/libtorrent-rasterbar.so" 2>/dev/null || true
echo "====> Verifying package contents:"
echo "====> Runtime package contents:"
find "$TARGET_DESTDIR/pkg_runtime" -type f | sort
echo "====> Development package contents:"
find "$TARGET_DESTDIR/pkg_dev" -type f | sort
echo "====> Python package contents:"
find "$TARGET_DESTDIR/pkg_python" -type f | sort
echo "====> Packaging complete"
echo "Runtime package directory: $TARGET_DESTDIR/pkg_runtime"
echo "Development package directory: $TARGET_DESTDIR/pkg_dev"
echo "Python package directory: $TARGET_DESTDIR/pkg_python"
echo "====> All done!"
exit 0
