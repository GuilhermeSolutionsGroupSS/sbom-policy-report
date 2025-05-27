#!/usr/bin/env bash
set -euo pipefail

API_URL="https://api.boostsecurity.io/sbom-inventory/graphql"
TOKEN=$BOOST_API_TOKEN
TMP_DIR="temp-results"
FILE_NAME="sbom_export.csv"

rm -f $TMP_DIR/$FILE_NAME

echo "Requesting SBOM report (CSV)..."
GENERATE_PAYLOAD='{
  "operationName": "generateSbomReport",
  "variables": {
    "outputFormat": "CSV",
    "filters": { "withVulnerabilities": false }
  },
  "query": "mutation generateSbomReport($outputFormat: BomFormat!, $analysisId: String, $filters: GenerateReportFiltersSchema) { generateReport(outputFormat: $outputFormat analysisId: $analysisId filters: $filters) { ... on OperationError { errorType errorMessage __typename } ... on Report { id status downloadUrl __typename } __typename } }"
}'


### 1. Generate report ###
resp=$(curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: ApiKey $TOKEN" \
  -d "$GENERATE_PAYLOAD")

report_id=$(jq -r '.data.generateReport.id' <<<"$resp")
status=$(jq -r '.data.generateReport.status' <<<"$resp")
echo "Report ID: $report_id, status: $status"

### 2. Try until READY ###
while [[ "$status" != "READY" ]]; do
  echo "Waiting 2s for report to be READY (current: $status)..."
  sleep 2
  STATUS_PAYLOAD='{
    "operationName": "sbomReport",
    "variables": { "id": "'"$report_id"'" },
    "query": "query sbomReport($id: ID!) { report(id: $id) { id status downloadUrl __typename } }"
  }'
  resp=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: ApiKey $TOKEN" \
    -d "$STATUS_PAYLOAD")
  status=$(jq -r '.data.report.status' <<<"$resp")
  download_url=$(jq -r '.data.report.downloadUrl' <<<"$resp")
done

echo "Report READY. Downloading CSV..."

### 3. Download CSV ###
curl -s -L "$download_url" -o $TMP_DIR/$FILE_NAME

echo "SBOM export saved as $TMP_DIR/$FILE_NAME"
