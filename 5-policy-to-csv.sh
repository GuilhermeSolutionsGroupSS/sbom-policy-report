#!/usr/bin/env python3
import csv
import json
import sys
import os

# Configuration
TMP_DIR = 'temp-results'
INPUT_CSV = os.path.join(TMP_DIR, '3-sbom_export_with_repos.csv')
JSON_FILE1 = os.path.join(TMP_DIR, '4-resources-gitlab.json')
JSON_FILE2 = os.path.join(TMP_DIR, '4-resources-github.json')
OUTPUT_CSV = 'COMPLETE_SBOM_WITH_POLICIES.csv'

# Load repo-to-policy mapping from JSON
def load_policy_map(json_path):
    with open(json_path, 'r') as jf:
        data = json.load(jf)
    edges = (
        data.get('data', {})
            .get('provider', {})
            .get('collection', {})
            .get('resources', {})
            .get('edges', [])
    )
    mapping = {}
    for edge in edges:
        node = edge.get('node', {})
        repo_name = node.get('name', '').strip()
        policy = node.get('policy', {})
        policy_name = policy.get('name', '')
        if repo_name:
            mapping[repo_name] = policy_name
    return mapping

# Main
def main():
    # ensure input CSV exists
    if not os.path.isfile(INPUT_CSV):
        sys.exit(f"Error: input CSV '{INPUT_CSV}' not found.")
    # ensure at least one JSON file exists
    if not os.path.isfile(JSON_FILE1) and not os.path.isfile(JSON_FILE2):
        sys.exit(f"Error: neither JSON file found: {JSON_FILE1}, {JSON_FILE2}")

    # load both maps (empty if missing)
    map1 = load_policy_map(JSON_FILE1) if os.path.isfile(JSON_FILE1) else {}
    map2 = load_policy_map(JSON_FILE2) if os.path.isfile(JSON_FILE2) else {}

    with open(INPUT_CSV, newline='') as inf, open(OUTPUT_CSV, 'w', newline='') as outf:
        reader = csv.DictReader(inf)
        # filter out any empty or None fieldnames
        clean_fields = [f for f in reader.fieldnames if f]
        if 'policies' not in clean_fields:
            clean_fields.append('policies')
        writer = csv.DictWriter(outf, fieldnames=clean_fields)
        writer.writeheader()

        for row in reader:
            # remove stray None key
            row.pop(None, None)

            repos_field = row.get('Repositories', '').strip()
            policies = set()
            if repos_field:
                for repo in repos_field.split(';'):
                    name = repo.split('/')[-1]
                    # lookup first in gitlab map, then github
                    pol_name = map1.get(name) or map2.get(name)
                    if pol_name:
                        policies.add(pol_name)

            row['policies'] = ';'.join(sorted(policies))
            # only write known fields
            out_row = {k: row.get(k, '') for k in clean_fields}
            writer.writerow(out_row)

    print(f"✓ Wrote output with policies column to '{OUTPUT_CSV}'")

if __name__ == '__main__':
    main()
