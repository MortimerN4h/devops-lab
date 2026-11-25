#!/bin/sh
# Create the "notes" table (if missing) and add the sample notes (if the table is empty).
# The SAME script for both places:
#   local/CI  : the "dynamodb-init" container runs it against DynamoDB Local (AWS_ENDPOINT_URL is set)
#   production: run it ONCE from the bastion against the real table that Terraform created:
#               TABLE_NAME=<table> AWS_REGION=us-east-1 sh task_week1/apps/dotnet/db/init.sh
# AWS CLI v2 reads AWS_ENDPOINT_URL by itself: set = local, unset = real AWS.
set -eu
TABLE="${TABLE_NAME:-notes}"

# Wait until DynamoDB answers (DynamoDB Local is a Java program: it needs a few seconds after its container starts)
i=0
until aws dynamodb list-tables >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -ge 30 ] && { echo "DynamoDB not reachable"; exit 1; }
  sleep 1
done

if ! aws dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
  echo "Creating table $TABLE"
  # Only the KEY is declared: every other attribute is free-form (no schema, unlike SQL)
  aws dynamodb create-table --table-name "$TABLE" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE"
fi

COUNT=$(aws dynamodb scan --table-name "$TABLE" --select COUNT --query Count --output text)
if [ "$COUNT" != "0" ]; then
  echo "Table $TABLE already has $COUNT notes, skipping seed"
  exit 0
fi

day() { date -u -d "@$(( $(date +%s) + $1 * 86400 ))" +%Y-%m-%d; } # day N = today + N days
NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# put ID TEXT DONE [DUE]  -> one item. In DynamoDB JSON every value says its type: S = string, BOOL = boolean
put() {
  due=""
  [ -n "${4:-}" ] && due=", \"dueDate\": {\"S\": \"$4\"}"
  aws dynamodb put-item --table-name "$TABLE" --item \
    "{\"id\": {\"S\": \"$1\"}, \"text\": {\"S\": \"$2\"}, \"done\": {\"BOOL\": $3}, \"createdAt\": {\"S\": \"$NOW\"}$due}"
}
# Fixed UUIDv7-shaped ids, increasing = the order the API lists them (newest first = the last one)
put 00000000-0000-7000-8000-000000000001 "Learn Docker"        true  "$(day -2)"
put 00000000-0000-7000-8000-000000000002 "Learn Terraform"     false "$(day 0)"
put 00000000-0000-7000-8000-000000000003 "Deploy to AWS"       false "$(day 7)"
put 00000000-0000-7000-8000-000000000004 "Read the Nginx docs" false
echo "Seeded 4 notes into $TABLE"
