#!/bin/bash
# Aggregate Packages Script
# Ce script agrège les packages spécifiés dans packages.json

set -e

# Initialiser le fichier manifest
manifest_file="downloads/manifest.yaml"
echo "downloaded_assets: []" > "$manifest_file"

# Créer le dossier pour les téléchargements
mkdir -p downloads

# Fonction pour comparer des versions sémantiques
function version_gt() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

function cleanup_version() {
  # Nettoyer la version (retirer v, release-, etc.)
  version=$(echo "$1" | sed -E 's/^[vV]//; s/^release-//')
  echo "$version"
}

function extract_version_from_tag() {
  # Extraire juste la partie version d'un tag
  version=$(echo "$1" | grep -oP '\d+\.\d+\.\d+(?:-[a-zA-Z0-9.]+)?' || echo "$1")
  echo "$version"
}

function find_best_release() {
  local repo="$1"
  local version_req="$2"
  local tag_prefix="$3"
  
  # Obtenir toutes les releases
  releases=$(gh release list --repo "$repo" --limit 100 --json tagName,name,createdAt)
  
  # Si le préfixe de tag est spécifié, filtrer les releases
  if [[ -n "$tag_prefix" ]]; then
    filtered_releases=$(echo "$releases" | jq --arg prefix "$tag_prefix" '[.[] | select(.tagName | startswith($prefix))]')
    if [[ $(echo "$filtered_releases" | jq length) -eq 0 ]]; then
      echo "No releases with tag prefix '$tag_prefix' found in $repo" >&2
      return 1
    fi
    releases="$filtered_releases"
  fi
  
  # Si aucune exigence de version, retourner la dernière release
  if [[ -z "$version_req" ]]; then
    echo "$releases" | jq -r '.[0].tagName'
    return 0
  fi
  
  # Déterminer l'opérateur et la version requise
  if [[ "$version_req" == ">="* ]]; then
    operator=">="
    req_version="${version_req#>=}"
  else
    operator="=="
    req_version="$version_req"
  fi
  
  # Nettoyer la version requise
  req_version=$(cleanup_version "$req_version")
  
  # Cas d'une version exacte
  if [[ "$operator" == "==" ]]; then
    exact_tag=$(echo "$releases" | jq -r --arg req "$req_version" '.[] | select(.tagName == $req or .tagName == "v"+$req) | .tagName' | head -n 1)
    if [[ -n "$exact_tag" ]]; then
      echo "$exact_tag"
      return 0
    fi
    echo "No release with exact version '$req_version' found in $repo" >&2
    return 1
  fi
  
  # Cas d'une version minimale (>=)
  # Traiter toutes les versions et trouver la plus grande qui correspond
  best_tag=""
  best_version=""
  
  while IFS= read -r tag; do
    # Extraire et nettoyer la version
    tag_version=$(extract_version_from_tag "$tag")
    clean_tag_version=$(cleanup_version "$tag_version")
    
    # Vérifier si la version est >= à la version requise
    if version_gt "$clean_tag_version" "$req_version" || [[ "$clean_tag_version" == "$req_version" ]]; then
      # Si c'est notre première version valide ou si elle est plus grande que la meilleure actuelle
      if [[ -z "$best_version" ]] || version_gt "$clean_tag_version" "$best_version"; then
        best_version="$clean_tag_version"
        best_tag="$tag"
      fi
    fi
  done < <(echo "$releases" | jq -r '.[].tagName')
  
  if [[ -n "$best_tag" ]]; then
    echo "$best_tag"
    return 0
  else
    echo "No release matching '>= $req_version' found in $repo" >&2
    return 1
  fi
}

function process_package() {
  local package_json="$1"
  local name
  local repo
  local version_req
  local tag_prefix
  local enabled
  local zip_group
  local file_patterns
  
  name=$(echo "$package_json" | jq -r '.name')
  repo=$(echo "$package_json" | jq -r '.repo')
  version_req=$(echo "$package_json" | jq -r '.version // empty')
  tag_prefix=$(echo "$package_json" | jq -r '.tag_prefix // empty')
  enabled=$(echo "$package_json" | jq -r '.enabled // true')
  zip_group=$(echo "$package_json" | jq -r '.zip // empty')
  file_patterns=$(echo "$package_json" | jq -r '.file_patterns // [] | join("|")')
  
  # Vérifier si le package est activé
  if [[ "$enabled" != "true" ]]; then
    echo "Package $name is disabled, skipping"
    return 0
  fi
  
  echo "Processing package $name from $repo"
  echo "  Version requirement: $version_req"
  echo "  Tag prefix: $tag_prefix"
  
  # Trouver la meilleure release
  local best_tag
  if ! best_tag=$(find_best_release "$repo" "$version_req" "$tag_prefix"); then
    echo "Could not find suitable release for $name from $repo"
    return 1
  fi
  
  echo "  Selected release: $best_tag"
  
  # Télécharger les assets
  local download_dir="downloads"
  local assets
  local downloaded=0
  
  assets=$(gh release view "$best_tag" --repo "$repo" --json assets | jq -r '.assets[].name')
  
  for asset in $assets; do
    # Si des motifs de fichiers sont spécifiés, vérifier la correspondance
    if [[ -n "$file_patterns" ]]; then
      if ! echo "$asset" | grep -qE "$file_patterns"; then
        continue
      fi
    fi
    
    local dest_path="${download_dir}/${name}_${asset}"
    echo "  Downloading $asset to $dest_path"
    
    if gh release download "$best_tag" --repo "$repo" --pattern "$asset" --dir "$download_dir" --output "${name}_${asset}"; then
      ((downloaded++))
      
      # Ajouter au manifest
      yq -i ".downloaded_assets += [{\"name\": \"$asset\", \"category\": \"$name\", \"repository\": \"$repo\", \"tag\": \"$best_tag\"}]" "$manifest_file"
      
      # Ajouter au groupe zip si applicable
      if [[ -n "$zip_group" ]]; then
        echo "$dest_path" >> "zip_group_${zip_group}.txt"
      fi
    else
      echo "  Failed to download $asset"
    fi
  done
  
  echo "  Downloaded $downloaded assets for $name"
  return 0
}

function main() {
  local packages_json="packages.json"
  
  # Lire et traiter chaque package
  packages_count=$(jq '.packages | length' "$packages_json")
  echo "Found $packages_count packages in $packages_json"
  
  for i in $(seq 0 $((packages_count - 1))); do
    package_json=$(jq -c ".packages[$i]" "$packages_json")
    process_package "$package_json"
  done
  
  # Créer les archives zip pour chaque groupe
  for zip_group_file in zip_group_*.txt; do
    if [[ -f "$zip_group_file" ]]; then
      group_name="${zip_group_file#zip_group_}"
      group_name="${group_name%.txt}"
      
      echo "Creating ZIP archive for group: $group_name"
      cd downloads
      zip -r "${group_name}.zip" "$(xargs -n1 basename < "../$zip_group_file")"
      cd ..
      echo "  Created ${group_name}.zip"
      rm "$zip_group_file"
    fi
  done
  
  echo "Processing completed successfully!"
}

main 
