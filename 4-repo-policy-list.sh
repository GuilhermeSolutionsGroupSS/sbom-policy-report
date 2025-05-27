#!/bin/bash
set -euo pipefail

API_URL="https://api.boostsecurity.io/asset-management/graphql"
TMP_DIR="temp-results"
TOKEN=$BOOST_API_TOKEN


### GraphQL query to list orgs/groups (collections) ###
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
      }
      edges {
        node { collectionId }
      }
    }
  }
}'

### query to list repos (resources) in a org/group (collection) ###
GET_RESOURCES_QUERY='query getResources($providerId: String!, $collectionId: String!, $filters: Filters, $first: Int, $after: String, $last: Int, $before: String, $page: Int) {
  provider(providerId: $providerId, filters: $filters) {
    collection(collectionId: $collectionId) {
      resources(
        first: $first
        after: $after
        last: $last
        before: $before
        page: $page
      ) {
        totalCount
        pageInfo {
          hasNextPage
          __typename
        }
        edges {
          node {
            resourceId
            name
            policy {
              policyId
              name
            }
          }
        }
      }
    }
  }
}'

for PROVIDER in GITHUB GITLAB; do
  echo
  echo "============================================"
  echo "  SCM: $PROVIDER"
  echo "============================================"

  ### 1. Page through collections ####
  page=1
  hasNextPage=true
  collectionIds=()
  while [ "$hasNextPage" = "true" ]; do
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
    resp=$(curl -s -X POST "$API_URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: ApiKey  $TOKEN" \
      -d "$payload")
    hasNextPage=$(jq -r '.data.provider.collections.pageInfo.hasNextPage' <<<"$resp")
    # save IDs
    ids=( $(jq -r '.data.provider.collections.edges[].node.collectionId' <<<"$resp") )
    collectionIds+=("${ids[@]}")
    ((page++))
  done

  coll_file="$TMP_DIR/4-collections-${PROVIDER,,}.json"
  jq -n --argjson ids "$(printf '%s\n' "${collectionIds[@]}" | jq -R . | jq -s .)" \
    '{ data: { provider: { collectionIds: $ids } } }' > "$coll_file"
  echo "Saved all collection IDs to $coll_file"

  ### 2. Page through resources for each collection ###

  TMP_RES=$(mktemp)
  > "$TMP_RES"

  for COLL_ID in "${collectionIds[@]}"; do
    echo "  Collection $COLL_ID:"
    page=1
    hasNextPage=true
    while [ "$hasNextPage" = "true" ]; do
      payload=$(jq -n \
        --arg providerId "$PROVIDER" \
        --arg collectionId "$COLL_ID" \
        --argjson first 100 \
        --argjson page "$page" \
        --arg query "$GET_RESOURCES_QUERY" \
        '{
          operationName: "getResources",
          variables: {
            providerId: $providerId,
            collectionId: $collectionId,
            filters: {},
            first: $first,
            page: $page
          },
          query: $query
        }'
      )
      resp=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: ApiKey $TOKEN" \
        -d "$payload")

      if [ "$page" -eq 1 ]; then
        resTotal=$(jq '.data.provider.collection.resources.totalCount' <<<"$resp")
        echo "    Total resources: $resTotal"
      fi

      hasNextPage=$(jq -r '.data.provider.collection.resources.pageInfo.hasNextPage' <<<"$resp")
      
      jq -c --arg coll "$COLL_ID" \
        '.data.provider.collection.resources.edges[] | {collectionId: $coll} + .' \
        <<<"$resp" >> "$TMP_RES"
      ((page++))
    done
  done

  # write all in a single resources file
  res_file="$TMP_DIR/4-resources-${PROVIDER,,}.json"
  jq -n --slurpfile edges "$TMP_RES" \
     '{ data: { resources: { edges: $edges } } }' > "$res_file"
  rm "$TMP_RES"

done

echo ""
echo "Done."
