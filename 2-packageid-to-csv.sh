#!/usr/bin/env python3
import csv
import json
import sys
import os

### Env vars ###
TMP_DIR = 'temp-results'
INPUT_CSV = os.path.join(TMP_DIR, 'sbom_export.csv')
PACKAGES_JSON = os.path.join(TMP_DIR, '1-packageids.json')
OUTPUT_CSV = os.path.join(TMP_DIR, '2-sbom_export_with_ids.csv')

with open(PACKAGES_JSON, 'r') as pf:
    pkg_data = json.load(pf)
mapping = {pkg['purl']: pkg['packageId'] for pkg in pkg_data.get('packages', [])}

### read CSV and write outpuy ###
with open(INPUT_CSV, newline='') as infile, open(OUTPUT_CSV, 'w', newline='') as outfile:
    reader = csv.DictReader(infile)
    # make sure 'packageId' not already present
    fieldnames = reader.fieldnames.copy()
    if 'packageId' not in fieldnames:
        fieldnames.append('packageId')

    writer = csv.DictWriter(outfile, fieldnames=fieldnames)
    writer.writeheader()

    for row in reader:
        purl = row.get('purl', '').strip()
        row['packageId'] = mapping.get(purl, '')
        writer.writerow(row)

print(f"✓ Wrote output with packageId column to '{OUTPUT_CSV}'")
