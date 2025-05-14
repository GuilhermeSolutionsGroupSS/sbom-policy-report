#!/bin/bash
set -euo pipefail

API_URL="https://api.boostsecurity.io/asset-management/graphql"
read -p "Enter your Bearer Token: " TOKEN

# GraphQL query, preserved exactly as provided
GET_COLLECTIONS_QUERY='query getCollections($providerId: String!, $filters: Filters, $first: Int, $after: String, $last: Int, $before: String, $page: Int) {
  provider(providerId: $providerId, filters: $filters) {
    collections(
      first: $first
      after: $after
      last: $last
      before: $before
      page: $page
    ) {
      totalCount
      pageInfo {
        hasNextPage
        hasPreviousPage
        startCursor
        endCursor
        __typename
      }
      edges {
        cursor
        node {
          collectionId
          assetType
          name
          resources {
            totalCount
            __typename
          }
          __typename
        }
        __typename
      }
      __typename
    }
    __typename
  }
}'


for PROVIDER in GITLAB GITHUB; do
  echo "============================================"
  echo "Listing collections for provider: $PROVIDER"
  echo "============================================"
  page=1
  hasNextPage=true
  combinedEdges="[]"
  totalCount=0

  while [ "$hasNextPage" = "true" ]; do
    echo "Fetching page $page..."
    # Build the payload
    payload=$(jq -n \
      --arg providerId "$PROVIDER" \
      --argjson first 100 \
      --argjson page "$page" \
      --arg query "$GET_COLLECTIONS_QUERY" \
      '{
        operationName: "getCollections",
        variables: {
          providerId: $providerId,
          filters: {},
          first: $first,
          page: $page
        },
        query: $query
      }'
    )

    # Execute the request
    response=$(curl -s -X POST "$API_URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TOKEN" \
      -d "$payload")

    # On first page, record totalCount
    if [ "$page" -eq 1 ]; then
      totalCount=$(jq '.data.provider.collections.totalCount' <<<"$response")
      echo "Total collections: $totalCount"
    fi

    # Extract edges and pageInfo
    edges=$(jq '.data.provider.collections.edges' <<<"$response")
    hasNextPage=$(jq -r '.data.provider.collections.pageInfo.hasNextPage' <<<"$response")

    # Merge into combinedEdges
    combinedEdges=$(jq -n --argjson a "$combinedEdges" --argjson b "$edges" '$a + $b')

    ((page++))
  done

  # Write out final JSON
  out_file="collections-${PROVIDER,,}.json"
  jq -n \
    --argjson edges "$combinedEdges" \
    --argjson totalCount "$totalCount" \
    '{
      data: {
        provider: {
          collections: {
            totalCount: ($totalCount | tonumber),
            edges: $edges
          }
        }
      }
    }' > "$out_file"

  echo "Saved all collections to $out_file"
  echo
done


