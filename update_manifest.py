#!/usr/bin/env python3

import yaml
import sys
import os
import argparse
import json
import copy

def load_yaml(yaml_path):
    """Load the YAML file."""
    print(f"Loading the YAML file from '{yaml_path}'...")
    with open(yaml_path, 'r') as f:
        data = yaml.safe_load(f)
    print("YAML file loaded successfully.")
    return data

def save_yaml_if_changed(original_data, updated_data, yaml_path):
    """Save the YAML file only if there are changes."""
    if original_data != updated_data:
        print(f"Changes detected. Saving updated manifest in '{yaml_path}'...")
        with open(yaml_path, 'w') as f:
            yaml.dump(updated_data, f, sort_keys=False)
        print("Manifest saved successfully.")
    else:
        print("No changes detected. Save operation ignored.")

def update_package_entry(manifest, package_id, checksum, build_date, package_version, category, tag=None, build=None):
    """
    Update or add a package entry in the manifest using
    a flat structure, without runtime/development distinction.

    The expected structure is:
    packages:
        <package_id>:
            <version>: { checksum_sha256, build_date, build, category, tag, distribution }
    """
    print(f"Updating entry for package '{package_id}', version '{package_version}', build '{build}'...")
    if 'packages' not in manifest or not isinstance(manifest['packages'], dict):
        manifest['packages'] = {}
        print("'packages' key initialized in the manifest.")
    
    if package_id not in manifest['packages']:
        manifest['packages'][package_id] = {}
        print(f"New entry created for the package '{package_id}'.")
    
    manifest['packages'][package_id][package_version] = {
        'checksum_sha256': checksum,
        'build_date': build_date,
        'build': build,
        'category': category,
        'tag': tag,
        'distribution': ['bookworm']
    }
    print(f"Package '{package_id}', version '{package_version}', build '{build}' mis à jour.")

def update_application_entry(manifest, application_id, build_date, application_info):
    """
    Updates or adds an application entry in the manifest.
    """
    print(f"Updated entry for application '{application_id}'...")
    if 'applications' not in manifest:
        manifest['applications'] = {}
        print("Key 'applications' initialized in manifest.")
    
    manifest['applications'][application_id] = {
        'build_date': build_date,
        'dependencies': application_info.get('dependencies', []),
        'packages': application_info.get('packages', {})
    }
    print(f"Application '{application_id}' updated.")

def main():
    print("Starting the update_manifest.py script...")
    parser = argparse.ArgumentParser(description='Updates manifest.yaml for packages or applications.')
    parser.add_argument('repo_path', help='Path to the binaries directory.')
    parser.add_argument('updates', help='JSON string containing package or application updates.')
    args = parser.parse_args()

    repo_path = args.repo_path
    updates_json = args.updates

    print("Arguments parsés :")
    print(f"  repo_path: {repo_path}")
    print(f"  updates: {updates_json}")

    try:
        updates = json.loads(updates_json)
    except json.JSONDecodeError as e:
        print(f"Error parsing update JSON : {e}")
        sys.exit(1)

    manifest_path = os.path.join(repo_path, "manifest.yaml")
    if not os.path.isfile(manifest_path):
        print(f"Error: manifest file '{manifest_path}' does not exist.")
        sys.exit(1)
    else:
        print(f"Manifest trouvé : '{manifest_path}'.")

    original_manifest = load_yaml(manifest_path)
    updated_manifest = copy.deepcopy(original_manifest)

    if 'package_updates' in updates:
        print("Processing package updates...")
        package_updates = updates['package_updates']
        for category_key, versions in package_updates.items():
            for package_version, package_info in versions.items():
                checksum = package_info.get('checksum_sha256')
                package_id = package_info.get('package_id')
                build_date = package_info.get('build_date')
                tag = package_info.get('tag')
                category = package_info.get('category')
                build = package_info.get('build')
                if package_id in ["libtorrent21", "libtorrent22", "libtorrent24"]:
                    package_id = "libtorrent"
                if not checksum:
                    print(f"Error: No checksum provided for package '{package_id}'.")
                    sys.exit(1)
                if not package_version:
                    print(f"Error: No version provided for package '{package_id}'.")
                    sys.exit(1)
                if not build_date:
                    print(f"Error: No build date provided for package '{package_id}'.")
                    sys.exit(1)
                if not build:
                    print(f"Error: No build provided for package '{package_id}'.")
                    sys.exit(1)
                update_package_entry(
                    manifest=updated_manifest,
                    package_id=package_id,
                    checksum=checksum,
                    build_date=build_date,
                    package_version=package_version,
                    category=category,
                    tag=tag,
                    build=build
                )

    if 'application_updates' in updates:
        print("Processing application updates...")
        application_updates = updates['application_updates']
        for application_id, application_info in application_updates.items():
            build_date = application_info.get('build_date', None)
            update_application_entry(
                manifest=updated_manifest,
                application_id=application_id,
                build_date=build_date,
                application_info=application_info
            )

    save_yaml_if_changed(original_manifest, updated_manifest, manifest_path)
    print("Manifest updated successfully.")

if __name__ == "__main__":
    main()
