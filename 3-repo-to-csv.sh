#!/usr/bin/env python3
import os
import csv
import requests
import sys
import time

### Constants ###
TMP_DIR = 'temp-results'
INPUT_CSV = os.path.join(TMP_DIR, '2-sbom_export_with_ids.csv')
OUTPUT_CSV = os.path.join(TMP_DIR, '3-sbom_export_with_repos.csv')
API_URL = 'https://api.boostsecurity.io/sbom-inventory/graphql'
TOKEN_ENV = 'BOOST_API_TOKEN'
PAGE_SIZE = 100

### GraphQL query ###
GET_REPOS_QUERY = '''query getListRepos(
  $first: Int,
  $page: Int,
  $search: String,
  $packageIds: [String!]
) {
  analyses(
    first: $first,
    page: $page,
    filters: { search: $search, packageIds: $packageIds }
  ) {
    edges {
      node {
        organizationName
        projectName
      }
    }
    pageInfo {
      hasNextPage
    }
  }
}'''

### Token Management ###
def get_token():
    token = os.getenv(TOKEN_ENV)
    if not token:
        print(f"Error: environment variable {TOKEN_ENV} not set.", file=sys.stderr)
        sys.exit(1)
    return token

def update_headers(token):
    return {
        'Content-Type': 'application/json',
        'Authorization': f'ApiKey {token}'
    }

def make_request(payload, headers):
    response = requests.post(API_URL, json=payload, headers=headers)
    if response.status_code == 502:
        print("Warning: Received 502 from API, skipping this page.")
        return {'data': {'analyses': {'edges': [], 'pageInfo': {'hasNextPage': False}}}}
    response.raise_for_status()
    return response.json()

### Main Script ###
token = get_token()
headers = update_headers(token)

start_time = time.time()
last_pause = start_time

with open(INPUT_CSV, newline='') as inf, open(OUTPUT_CSV, 'w', newline='') as outf:
    reader = csv.DictReader(inf)
    fieldnames = reader.fieldnames.copy()
    if 'Repositories' not in fieldnames:
        fieldnames.append('Repositories')
    writer = csv.DictWriter(outf, fieldnames=fieldnames)
    writer.writeheader()

    for row in reader:
        pkg_id = row.get('packageId', '').strip()
        if not pkg_id:
            row['Repositories'] = ''
            writer.writerow(row)
            continue

        repos = set()
        page = 1
        while True:
            if time.time() - last_pause >= 15 * 60:
                print("1 minute pause to avoid block")
                time.sleep(60)
                print("continuing...")
                last_pause = time.time()

            payload = {
                'operationName': 'getListRepos',
                'query': GET_REPOS_QUERY,
                'variables': {
                    'first': PAGE_SIZE,
                    'page': page,
                    'search': '',
                    'packageIds': [pkg_id]
                }
            }
            json_data = make_request(payload, headers)
            data = json_data.get('data', {}).get('analyses', {})

            for edge in data.get('edges', []):
                node = edge.get('node', {})
                org = node.get('organizationName', '')
                proj = node.get('projectName', '')
                if org and proj:
                    repos.add(f"{org}/{proj}")

            if not data.get('pageInfo', {}).get('hasNextPage'):
                break
            page += 1

        row['Repositories'] = ';'.join(sorted(repos))
        writer.writerow(row)

print(f"Wrote output with Repositories column to '{OUTPUT_CSV}'")
