#!/bin/bash
set -e

TMP_DIR="temp-results"

# Make sure all files are executable
chmod +x 0-sbom-csv-download.sh
chmod +x 1-sbom-packages.sh
chmod +x 2-packageid-to-csv.sh
chmod +x 3-repo-to-csv.sh
chmod +x 4-repo-policy-list.sh
chmod +x 5-policy-to-csv.sh

# Make sure jq is present
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is not installed. Installing jq..."
  sudo apt-get update && sudo apt-get install -y jq
fi

read -p "Enter your Bearer Token: " TOKEN
export BOOST_TOKEN=$TOKEN

read -p "Enter your API Token: " API_TOKEN
export BOOST_API_TOKEN=$API_TOKEN

mkdir -p $TMP_DIR

echo "#### START STEP 0 ####"
# Step 0
echo "Running 0-sbom-csv-download.sh..."
./0-sbom-csv-download.sh

echo "#### START STEP 1 ####"
# Step 1
if [ ! -f temp-results/1-packageids.json ]; then
  echo "Running 1-sbom-packages.sh..."
  ./1-sbom-packages.sh
fi

echo "#### START STEP 2 ####"
# Step 2
if [ ! -f temp-results/2-sbom_export_with_ids.csv ]; then
  echo "Running 2-packageid-to-csv.sh..."
  ./2-packageid-to-csv.sh
fi

echo "#### START STEP 3 ####"
# Step 3
if [ ! -f temp-results/3-sbom_export_with_repos.csv ]; then
  echo "Running 3-repo-to-csv.sh..."
  echo "This step may take long. You can check it's progress in the file temp-results/3-sbom_export_with_repos.csv"
  ./3-repo-to-csv.sh
fi

echo "#### START STEP 4 ####"
# Step 4
if [ ! -f temp-results/4-resources-gitlab.json ]; then
  echo "Running 4-repo-policy-list.sh..."
  ./4-repo-policy-list.sh
fi

echo "#### START STEP 5 ####"
# Step 5
if [ ! -f temp-results/5-policy-to-csv.sh ]; then
  echo "Running 5-policy-to-csv.sh..."
  ./5-policy-to-csv.sh
else
  echo "You already have the final file. You don't need to run the script again."
fi
