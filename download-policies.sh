#!/bin/bash

function usage() {
  echo "Usage: $0 [--attached] [--local]" >&2
  echo "Options:" >&2
  echo "  --attached, -A  List only attached policies" >&2
  echo "  --local, -L     List only local policies" >&2
  echo "  --help, -H      This" >&2
  exit 0
}

function fetch_policy() {
  policy_name=$(basename "$arn")
  echo "ARN Policy: $arn"
  # Retrieve the default version of the policy
  [[ -n $DEBUG ]] && echo "Fetching default version for policy: $arn"
  default_version=$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text)
  if [ $? -ne 0 ] || [ -z "$default_version" ]; then
    echo "Error retrieving default version for policy: $arn" >&2
    return
  fi
  [[ -n $DEBUG ]] && echo "Default version for $policy_name is $default_version"
  # Retrieve the policy version document
  [[ -n $DEBUG ]] && echo "Fetching policy JSON file from ARN: $arn"
  policy_json=$(aws iam get-policy-version --policy-arn "$arn" --version-id "$default_version" --query 'PolicyVersion.Document' --output json)
  if [ $? -ne 0 ]; then
    echo "Error retrieving policy version document for policy: $arn with version: $default_version" >&2
    return
  fi
  [[ -n $DEBUG ]] && {
    # Print JSON output
    echo "Policy JSON for $arn:"
    echo "$policy_json"
  }
  # Save the policy JSON
  echo "$policy_json" > "policies/${policy_name}.json"
  echo "Saved policy document for $policy_name"
}
# Step 1: List all policies and save their ARNs to a file, one per line
echo "Listing all policy ARNs..."

# Apply filter
unset FILTER
if [[ "$*" == *"--attached"* ]] || [[ "$*" == *"-A"* ]]; then
  FILTER="${FILTER} --only-attached"
  attached=Attached # Append to ZIP file name
  echo "Filtering attached policies"
fi
if [[ "$*" == *"--local"* ]] || [[ "$*" == *"-L"* ]]; then
  FILTER="${FILTER} --scope Local"
  local=Local # Append to ZIP file name
  echo "Filtering local (Customer Managed) policies"
fi
if [[ "$*" == *"--help"* ]] || [[ "$*" == *"-H"* ]]; then
  usage
fi

aws iam list-policies ${FILTER} --query 'Policies[*].Arn' --output text | tr '\t' '\n' > policy_arns.txt
if [ $? -ne 0 ]; then
  echo "Error listing policies"
  exit 1
fi
# Step 2: Create a directory to store policy documents if it doesn't exist
mkdir -p policies
# Step 3: Retrieve each policy document
while IFS= read -r arn; do
  if [ -n "$arn" ]; then
    fetch_policy &
  else
    echo "Empty ARN encountered, skipping..." >&2
  fi
done < policy_arns.txt
wait && echo "Background jobs completed"

# Step 4: Create a zip file containing all policy documents
echo "Creating zip file of all policy documents..."

ZIP_NAME=policies${attached}${local}.zip
zip -r $ZIP_NAME policies
# Optional: Cleanup
echo "Cleaning up..."
rm policy_arns.txt
rm -rf policies
echo "Done."
