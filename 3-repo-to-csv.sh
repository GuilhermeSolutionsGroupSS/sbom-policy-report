#!/usr/bin/env python3
import os
import csv
import requests
import sys

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
        token = input("Token not found in environment. Please enter a valid token: ").strip()
    return token

def update_headers(token):
    return {
        'Content-Type': 'application/json',
        'Authorization': f'ApiKey {token}'
    }

def make_request_with_retry(payload, headers):
    while True:
        response = requests.post(API_URL, json=payload, headers=headers)
        if response.status_code in {401, 502, 503, 504}:
            print("Token expired or invalid. Please enter a new token.")
            new_token = input("New token: ").strip()
            headers['Authorization'] = f'ApiKey {new_token}'
        else:
            response.raise_for_status()
            return response.json()

### Main Script ###
token = get_token()
headers = update_headers(token)

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
            json_data = make_request_with_retry(payload, headers)
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