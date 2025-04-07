#!/bin/bash
# Script pour générer des fichiers de métadonnées JSON pour les packages Debian
# Usage: ./generate_metadata.sh [options] path/to/debian/package.deb
#
# Options:
#   --category VALUE   Catégorie du package (ex: libtorrent-rasterbar)
#   --tag VALUE        Tag du package (ex: stable, oldstable, next)
#   --version VALUE    Version explicite (sinon extraite du nom du package)
#   --build VALUE      Numéro de build (par défaut: 1build1)
#   --extra KEY=VALUE  Ajouter des champs supplémentaires (peut être utilisé plusieurs fois)
#   --dep KEY=VALUE    Ajouter des dépendances (peut être utilisé plusieurs fois)

set -e  # Exit on error

CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DISTRIBUTION='["bookworm"]'
BUILD="1build1"
EXTRA_FIELDS=()
DEPENDENCIES=()

function usage {
    echo "Usage: $0 [options] path/to/debian/package.deb"
    echo "Options:"
    echo "  --category VALUE   Catégorie du package (ex: libtorrent-rasterbar)"
    echo "  --tag VALUE        Tag du package (ex: stable, oldstable, next)"
    echo "  --version VALUE    Version explicite (sinon extraite du nom du package)"
    echo "  --build VALUE      Numéro de build (par défaut: 1build1)"
    echo "  --extra KEY=VALUE  Ajouter des champs supplémentaires (peut être utilisé plusieurs fois)"
    echo "  --dep KEY=VALUE    Ajouter des dépendances (peut être utilisé plusieurs fois)"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

# Analyser les arguments
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
        --extra)
            if [[ "$2" == *=* ]]; then
                EXTRA_FIELDS+=("$2")
                shift 2
            else
                echo "Format incorrect pour --extra. Utilisez KEY=VALUE"
                usage
            fi
            ;;
        --dep)
            if [[ "$2" == *=* ]]; then
                DEPENDENCIES+=("$2")
                shift 2
            else
                echo "Format incorrect pour --dep. Utilisez KEY=VALUE"
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
    echo "Erreur: Le fichier $DEB_PACKAGE n'existe pas."
    exit 1
fi

# Extraire les informations du fichier DEB
echo "Générer les métadonnées pour: $DEB_PACKAGE"
CHECKSUM=$(sha256sum "$DEB_PACKAGE" | awk '{print $1}')
PACKAGE_ID=$(basename "$DEB_PACKAGE" .deb)

# Extraire la version du nom de fichier si elle n'est pas spécifiée
if [ -z "$VERSION" ]; then
    # Essayer d'extraire la version du nom du package
    VERSION=$(echo "$PACKAGE_ID" | grep -oP '\d+\.\d+\.\d+(?:-\w+\d+)?' || echo "")
    if [ -z "$VERSION" ]; then
        VERSION=$(echo "$PACKAGE_ID" | grep -oP '\d+\.\d+' || echo "unknown")
    fi
fi

# Déterminer le type si non spécifié (pour les packages libtorrent)
if [ -z "$TYPE" ]; then
    if [[ "$DEB_PACKAGE" == *"python"* ]]; then
        TYPE="python-bindings"
    elif [[ "$DEB_PACKAGE" == *"dev"* ]]; then
        TYPE="dev"
    else
        TYPE="lib"
    fi
fi

# Déterminer la catégorie si non spécifiée
if [ -z "$CATEGORY" ]; then
    # Extraire le préfixe du nom du package
    CATEGORY=$(echo "$PACKAGE_ID" | grep -oP '^[a-zA-Z0-9-]+' || echo "unknown")
fi

# Déterminer le tag si non spécifié
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

# Vérifier si jq est installé
if ! command -v jq &> /dev/null; then
    echo "Erreur: jq n'est pas installé. Veuillez l'installer pour générer les métadonnées."
    exit 1
fi

# Créer le JSON de base avec jq
JSON_FILE="${PACKAGE_ID}.json"

# Construire les arguments pour jq
JQ_ARGS=(
    --arg package_id "$PACKAGE_ID"
    --arg version "$VERSION"
    --arg build "$BUILD"
    --arg checksum_sha256 "$CHECKSUM"
    --arg build_date "$CURRENT_DATE"
    --arg category "$CATEGORY"
    --arg tag "$TAG"
    --arg type "$TYPE"
    --argjson distribution "$DISTRIBUTION"
)

# Construire la commande jq de base
JQ_FILTER="{
    package_id: \$package_id,
    version: \$version,
    build: \$build,
    checksum_sha256: \$checksum_sha256,
    build_date: \$build_date,
    category: \$category,
    tag: \$tag,
    type: \$type,
    distribution: \$distribution
}"

# Ajouter les champs supplémentaires
for field in "${EXTRA_FIELDS[@]}"; do
    KEY="${field%%=*}"
    VALUE="${field#*=}"
    JQ_ARGS+=(--arg "extra_${KEY}" "$VALUE")
    # Ajouter le champ au filtre jq en utilisant la substitution de motif Bash
    JQ_FILTER="${JQ_FILTER/\}/,\"${KEY}\": \$extra_${KEY}\}}"
done

# Ajouter les dépendances si présentes
if [ ${#DEPENDENCIES[@]} -gt 0 ]; then
    # Créer un objet de dépendances
    DEP_FILTER="{}"
    
    for dep in "${DEPENDENCIES[@]}"; do
        KEY="${dep%%=*}"
        VALUE="${dep#*=}"
        JQ_ARGS+=(--arg "dep_${KEY}" "$VALUE")
        # Ajouter la dépendance à l'objet de dépendances en utilisant la substitution de motif Bash
        DEP_FILTER="${DEP_FILTER/\}/,\"${KEY}\": \$dep_${KEY}\}}"
    done
    
    # Nettoyer la première virgule en utilisant la substitution de motif Bash
    DEP_FILTER="${DEP_FILTER/\{\,/\{}"
    
    # Ajouter l'objet de dépendances au filtre principal
    JQ_FILTER="$JQ_FILTER | . + {dependencies: $DEP_FILTER}"
fi

# Générer le JSON
jq "${JQ_ARGS[@]}" "$JQ_FILTER" > "$JSON_FILE" <<< "{}"

echo "Fichier de métadonnées généré: $JSON_FILE"
echo "Contenu:"
cat "$JSON_FILE" 
