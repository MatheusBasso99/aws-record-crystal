#!/usr/bin/env bash
# Runs the integration suite against DynamoDB Local.
#
# If something already answers on DYNAMODB_ENDPOINT (default http://localhost:8000) it is used as is;
# otherwise a container is started with docker compose and stopped again afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
ENDPOINT=${DYNAMODB_ENDPOINT:-http://localhost:8000}

list_tables() {
  curl -sf -m 3 -X POST "$ENDPOINT/" \
    -H 'Content-Type: application/x-amz-json-1.0' \
    -H 'X-Amz-Target: DynamoDB_20120810.ListTables' \
    -H 'Authorization: AWS4-HMAC-SHA256 Credential=x/20260101/us-east-1/dynamodb/aws4_request, SignedHeaders=host, Signature=x' \
    -d '{}' >/dev/null
}

if list_tables; then
  echo "using the DynamoDB Local already listening on $ENDPOINT"
else
  echo "starting DynamoDB Local with docker compose"
  docker compose -f docker/docker-compose.yml up -d
  trap 'docker compose -f docker/docker-compose.yml down' EXIT
  for _ in $(seq 1 30); do list_tables && break; sleep 2; done
fi

AWS_INTEGRATION=1 DYNAMODB_ENDPOINT="$ENDPOINT" AWS_REGION=us-east-1 AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local \
  crystal spec --error-on-warnings --tag integration spec/integration
