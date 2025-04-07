#!/usr/bin/env python3

import json
import subprocess
import os
import re
from collections import defaultdict

REPOS = [
    "deluge-builds",
    "qbittorrent-builds",
    "transmission-builds",
    "rtorrent-builds",
    "qBittorrent-builds"
]
ORG = "MediaEase-binaries"
OUTPUT_DIR = "packages"

def get_releases(repo):
    cmd = f"env -u GITHUB_TOKEN gh api /repos/{ORG}/{repo}/releases"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return json.loads(result.stdout)

def get_asset_content(asset_url):
    cmd = f"curl -sL '{asset_url}'"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON from {asset_url}: {str(e)}")
        return None

def get_package_info_from_json(assets, deb_name):
    json_name = deb_name.replace('.deb', '.json')
    for asset in assets:
        if asset['name'] == json_name:
            return get_asset_content(asset['browser_download_url'])
    print(f"❌ No JSON file found for {deb_name}")
    return None

def get_base_package_name(pkg_id):
    return re.sub(r'_\d.*', '', pkg_id)

def organize_all():
    distribution_data = defaultdict(lambda: defaultdict(list))

    for repo in REPOS:
        print(f"\n📦 Processing repo: {repo}")
        releases_data = get_releases(repo)
        print(f"→ Found {len(releases_data)} releases")

        for release in releases_data:
            assets = release.get('assets', [])
            print(f"→ Processing release {release['name']} ({len(assets)} assets)")

            for asset in assets:
                if not asset['name'].endswith('.deb'):
                    continue

                package_info = get_package_info_from_json(assets, asset['name'])
                if not package_info:
                    continue
                if 'os' not in package_info:
                    print(f"⚠️  Missing 'os' in JSON for {asset['name']}, skipping.")
                    continue

                distro = package_info['os']
                package_name = get_base_package_name(package_info['package_id'])

                entry = {
                    "name": asset['name'],
                    "version": package_info['version'],
                    "stability": package_info['tag'],
                    "checksum_sha256": package_info['checksum_sha256'],
                    "url": asset['browser_download_url']
                }

                distribution_data[distro][package_name].append(entry)
                print(f"✔️  Added {asset['name']} → {distro}/{package_name}")

    return distribution_data

def save_json_files(distribution_data):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for distro, packages in distribution_data.items():
        filename = os.path.join(OUTPUT_DIR, f"packages_{distro}.json")
        with open(filename, 'w') as f:
            json.dump(packages, f, indent=2)
        print(f"📁 Saved {filename}")

def main():
    print("🔍 Generating package summaries from selected repos...")
    data = organize_all()
    if not data:
        print("❌ No data generated.")
        return
    save_json_files(data)
    print("✅ Done.")

if __name__ == "__main__":
    main()
