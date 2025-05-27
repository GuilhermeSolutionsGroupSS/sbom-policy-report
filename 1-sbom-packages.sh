#!/bin/bash
set -euo pipefail

API_URL="https://api.boostsecurity.io/sbom-inventory/graphql"
TMP_DIR="temp-results"
TOKEN=$BOOST_TOKEN

### GraphQL query to list packages ###
GET_PACKAGES_QUERY='query getPackagesV2($first: Int, $after: String, $last: Int, $before: String, $page: Int, $filters: PackageFiltersSchema) {
  packages(
    first: $first
    after: $after
    last: $last
    before: $before
    page: $page
    filters: $filters
  ) {
    totalCount
    edges {
      node {
        packageId
        name
        version
        purl
      }
      cursor
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}'

echo
echo "Fetching packages (no vuln/fixable/EOL)..."

# temp file to keep each package (node)
TMP_NODES=$(mktemp)
> "$TMP_NODES"

page=1
hasNextPage=true
totalCount=0

while [ "$hasNextPage" = "true" ]; do
  echo "  → Fetching page $page..."
  payload=$(jq -n \
    --argjson first 100 \
    --argjson page "$page" \
    --argjson filters '{"withVulnerabilities":false,"isFixable":false,"isEndOfLife":false}' \
    --arg query "$GET_PACKAGES_QUERY" \
    '{
      operationName: "getPackagesV2",
      query: $query,
      variables: {
        first: $first,
        page: $page,
        filters: $filters
      }
    }'
  )

  resp=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "$payload")

  if [ "$page" -eq 1 ]; then
    totalCount=$(jq '.data.packages.totalCount' <<<"$resp")
    totalPages=$(( (totalCount + 99) / 100 ))
    echo "    Total pages: $totalPages"
  fi

  # extract only the four fields from each node
  jq -c '.data.packages.edges[].node 
         | {packageId, name, version, purl}' \
    <<<"$resp" >> "$TMP_NODES"

  hasNextPage=$(jq -r '.data.packages.pageInfo.hasNextPage' <<<"$resp")
  ((page++))
done

# collapse into one JSON file
out_file="1-packageids.json"
jq -s --arg totalCount "$totalCount" '{
  totalCount: ($totalCount|tonumber),
  packages: .
}' "$TMP_NODES" > "$TMP_DIR/$out_file"

rm "$TMP_NODES"

echo ""
echo "Saved all packages to $out_file"
