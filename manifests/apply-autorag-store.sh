#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
oc apply -f manifests/autorag/pgvector.yaml
oc apply -f manifests/autorag/vector-stores-cm.yaml
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type merge -p '{
  "spec":{"dashboardConfig":{"autorag":true,"externalVectorStores":true,"genAiStudio":true}}
}'
oc rollout status deploy/pgvector -n llm --timeout=180s || true
echo "AI asset endpoints → Vector stores: workshop-pgvector"
