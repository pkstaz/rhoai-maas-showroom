#!/usr/bin/env bash
# Build the workshop A2A agent and deploy it in llm.
#
# Default: OpenShift internal registry (no quay credentials).
# Optional quay.io:
#   QUAY_IMAGE=quay.io/<user>/workshop-faq:lab bash manifests/apply-agent.sh
#   (build+push first: see módulo 21)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
NS="${NS:-llm}"
APP=workshop-faq
CTX="manifests/agents/workshop-agent"
QUAY_IMAGE="${QUAY_IMAGE:-}"

oc get ns "$NS" >/dev/null

echo "=== Dashboard AgentOps + catalog ==="
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type merge -p '{
  "spec":{"dashboardConfig":{
    "agentsCatalog":true,
    "agentOps":true,
    "agentConfigManagement":true,
    "genAiStudio":true
  }}
}'

if [[ -n "$QUAY_IMAGE" ]]; then
  IMAGE="$QUAY_IMAGE"
  echo "Using pre-pushed image $IMAGE"
else
  echo "=== BuildConfig in cluster registry ==="
  oc -n "$NS" new-build --binary --name="$APP" --strategy=docker \
    --to="${APP}:lab" 2>/dev/null || true
  oc -n "$NS" start-build "$APP" --from-dir="$CTX" --follow --wait
  IMAGE="image-registry.openshift-image-registry.svc:5000/${NS}/${APP}:lab"
fi

echo "=== Optional MaaS secret for the agent ==="
if [[ -n "${MAAS_URL:-}" && -n "${API_KEY:-}" ]]; then
  oc -n "$NS" create secret generic workshop-faq-maas \
    --from-literal=MAAS_URL="$MAAS_URL" \
    --from-literal=MAAS_API_KEY="$API_KEY" \
    --from-literal=MODEL_ID="${MODEL_ID:-publishers/llm/models/qwen3-06b}" \
    --dry-run=client -o yaml | oc apply -f -
fi

echo "=== Deploy ==="
# Replace default image if using quay
tmp=$(mktemp)
sed "s|image: image-registry.openshift-image-registry.svc:5000/llm/workshop-faq:lab|image: ${IMAGE}|" \
  manifests/agents/deploy.yaml > "$tmp"
oc apply -f "$tmp"
rm -f "$tmp"

oc rollout status deploy/"$APP" -n "$NS" --timeout=180s || true
oc get deploy,svc,route -n "$NS" "$APP"
echo
echo "AI asset endpoints → Agents (proyecto $NS). Playground: register/load the agent."
