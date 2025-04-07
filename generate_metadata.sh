#!/bin/bash
# Script to generate JSON metadata files for Debian packages
# Usage: ./generate_metadata.sh [options] path/to/debian/package.deb
#
# Options:
#   --category VALUE   Package category (e.g.: libtorrent-rasterbar)
#   --tag VALUE        Package tag (e.g.: stable, oldstable, next)
#   --version VALUE    Explicit version (otherwise extracted from package name)
#   --build VALUE      Build number (default: 1build1)
#   --os VALUE        Distribution name (e.g.: bullseye, jammy)
#   --extra KEY=VALUE  Add additional fields (can be used multiple times)
#   --dep KEY=VALUE    Add dependencies (can be used multiple times)

set -e  # Exit on error

CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD="1build1"
EXTRA_FIELDS=()
DEPENDENCIES=()
OS=""

function usage {
    echo "Usage: $0 [options] path/to/debian/package.deb"
    echo "Options:"
    echo "  --category VALUE   Package category (e.g.: libtorrent-rasterbar)"
    echo "  --tag VALUE        Package tag (e.g.: stable, oldstable, next)"
    echo "  --version VALUE    Explicit version (otherwise extracted from package name)"
    echo "  --build VALUE      Build number (default: 1build1)"
    echo "  --os VALUE         Distribution name (e.g.: bullseye, jammy)"
    echo "  --extra KEY=VALUE  Add additional fields (can be used multiple times)"
    echo "  --dep KEY=VALUE    Add dependencies (can be used multiple times)"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

# Parse arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build)
            BUILD="$2"
            shift 2
            ;;
        --os)
            OS="$2"
            shift 2
            ;;
        --extra)
            if [[ "$2" == *=* ]]; then
                EXTRA_FIELDS+=("$2")
                shift 2
            else
                echo "Incorrect format for --extra. Use KEY=VALUE"
                usage
            fi
            ;;
        --dep)
            if [[ "$2" == *=* ]]; then
                DEPENDENCIES+=("$2")
                shift 2
            else
                echo "Incorrect format for --dep. Use KEY=VALUE"
                usage
            fi
            ;;
        -h|--help)
            usage
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

DEB_PACKAGE="$1"

if [ ! -f "$DEB_PACKAGE" ]; then
    echo "Error: File $DEB_PACKAGE does not exist."
    exit 1
fi

# Extract information from DEB file
echo "Generating metadata for: $DEB_PACKAGE"
CHECKSUM=$(sha256sum "$DEB_PACKAGE" | awk '{print $1}')
PACKAGE_ID=$(basename "$DEB_PACKAGE" .deb)

# Extract version from filename if not specified
if [ -z "$VERSION" ]; then
    VERSION=$(echo "$PACKAGE_ID" | grep -oP '\d+\.\d+\.\d+(?:-\w+\d+)?' || echo "")
    if [ -z "$VERSION" ]; then
        VERSION=$(echo "$PACKAGE_ID" | grep -oP '\d+\.\d+' || echo "unknown")
    fi
fi

# Determine type if not specified
if [ -z "$TYPE" ]; then
    if [[ "$DEB_PACKAGE" == *"python"* ]]; then
        TYPE="python-bindings"
    elif [[ "$DEB_PACKAGE" == *"dev"* ]]; then
        TYPE="dev"
    else
        TYPE="lib"
    fi
fi

# Determine category if not specified
if [ -z "$CATEGORY" ]; then
    CATEGORY=$(echo "$PACKAGE_ID" | grep -oP '^[a-zA-Z0-9-]+' || echo "unknown")
fi

# Determine tag if not specified
if [ -z "$TAG" ]; then
    if [[ "$PACKAGE_ID" == *"oldstable"* ]]; then
        TAG="oldstable"
    elif [[ "$PACKAGE_ID" == *"stable"* ]]; then
        TAG="stable"
    elif [[ "$PACKAGE_ID" == *"next"* ]]; then
        TAG="next"
    else
        TAG="stable"
    fi
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it to generate metadata."
    exit 1
fi

# Build JSON
JSON_FILE="${PACKAGE_ID}.json"

# Prepare jq arguments
JQ_ARGS=(
    --arg package_id "$PACKAGE_ID"
    --arg version    "$VERSION"
    --arg build      "$BUILD"
    --arg checksum_sha256 "$CHECKSUM"
    --arg build_date "$CURRENT_DATE"
    --arg category   "$CATEGORY"
    --arg tag        "$TAG"
    --arg type       "$TYPE"
)

# Add OS if provided
if [ -n "$OS" ]; then
    JQ_ARGS+=(--arg os "$OS")
    JQ_FILTER="{package_id: \$package_id, version: \$version, build: \$build, checksum_sha256: \$checksum_sha256, build_date: \$build_date, category: \$category, tag: \$tag, type: \$type, os: \$os}"
else
    JQ_FILTER="{package_id: \$package_id, version: \$version, build: \$build, checksum_sha256: \$checksum_sha256, build_date: \$build_date, category: \$category, tag: \$tag, type: \$type}"
fi

# Add additional fields
for field in "${EXTRA_FIELDS[@]}"; do
    KEY="${field%%=*}"
    VALUE="${field#*=}"
    JQ_ARGS+=(--arg "extra_${KEY}" "$VALUE")
    JQ_FILTER="\${JQ_FILTER%\}}}, \"${KEY}\": \$extra_${KEY}}"
done

# Add dependencies
if [ ${#DEPENDENCIES[@]} -gt 0 ]; then
    DEP_FILTER="{}"
    for dep in "${DEPENDENCIES[@]}"; do
        KEY="${dep%%=*}"
        VALUE="${dep#*=}"
        JQ_ARGS+=(--arg "dep_${KEY}" "$VALUE")
        DEP_FILTER="\${DEP_FILTER%\}}}, \"${KEY}\": \$dep_${KEY}}"
    done
    DEP_FILTER="\${DEP_FILTER/\{,/{/}"
    JQ_FILTER="\$JQ_FILTER | . + {dependencies: $DEP_FILTER}"
fi

# Generate JSON
jq "${JQ_ARGS[@]}" "$JQ_FILTER" > "$JSON_FILE" <<< "{}"

echo "Metadata file generated: $JSON_FILE"
echo "Content:"
cat "$JSON_FILE"
