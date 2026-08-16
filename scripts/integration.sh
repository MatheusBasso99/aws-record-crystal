#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -f docker/docker-compose.yml up -d
trap 'docker compose -f docker/docker-compose.yml down' EXIT
for i in $(seq 1 30); do curl -sf -X POST http://localhost:8000/ -H 'Content-Type: application/x-amz-json-1.0' \
  -H 'X-Amz-Target: DynamoDB_20120810.ListTables' -H 'Authorization: AWS4-HMAC-SHA256 Credential=x/20260101/us-east-1/dynamodb/aws4_request, SignedHeaders=host, Signature=x' -d '{}' >/dev/null && break; sleep 2; done
AWS_INTEGRATION=1 DYNAMODB_ENDPOINT=http://localhost:8000 AWS_REGION=us-east-1 AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local \
  crystal spec --error-on-warnings --tag integration spec/integration
