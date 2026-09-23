#!/usr/bin/env bash
# NemoGuardrails (TrustyAI CRD). No FMS / GuardrailsOrchestrator.
# Usage:
#   bash manifests/apply-guardrails.sh              # CPU: Presidio + regex, /v1/guardrail/checks
#   MODE=maas bash manifests/apply-guardrails.sh    # + proxy /v1/chat/completions → MaaS Qwen
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODE="${MODE:-cpu}"
NS="${NS:-llm}"

echo "=== TrustyAI Managed (CRD NemoGuardrails) ==="
oc patch dsc default-dsc --type=merge -p '{
  "spec":{"components":{"trustyai":{"managementState":"Managed"}}}
}' >/dev/null
for i in $(seq 1 36); do
  T=$(oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="TrustyAIReady")].status}' 2>/dev/null || true)
  echo "try $i TrustyAIReady=$T"
  [[ "$T" == "True" ]] && break
  sleep 10
done

echo "=== Dashboard flag (optional UI) ==="
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type merge -p '{
  "spec":{"dashboardConfig":{"guardrails":true,"genAiStudio":true}}
}'

if [[ "$MODE" == "maas" ]]; then
  CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
  MAAS_V1_URL="${MAAS_V1_URL:-https://maas.${CLUSTER_DOMAIN}/v1}"
  if [[ -z "${API_KEY:-}" ]]; then
    API_KEY=$(curl -sk -X POST "${MAAS_V1_URL%/v1}/maas-api/v1/api-keys" \
      -H "Authorization: Bearer $(oc whoami -t)" \
      -H "Content-Type: application/json" \
      -d '{"name":"nemo-workshop","subscription":"qwen-authenticated","expiresIn":"8h"}' \
      | jq -r '.key')
  fi
  if [[ -z "${MODEL_ID:-}" ]]; then
    MODEL_ID=$(curl -sk "${MAAS_V1_URL}/models" \
      -H "Authorization: Bearer ${API_KEY}" | jq -r '.data[0].id')
  fi
  echo "MaaS ${MAAS_V1_URL} model=${MODEL_ID}"
  oc -n "$NS" create secret generic nemo-maas-token \
    --from-literal=token="${API_KEY}" \
    --dry-run=client -o yaml | oc apply -f -
  python3 - "$MAAS_V1_URL" "$MODEL_ID" <<'PY'
import sys
from pathlib import Path
base, model = sys.argv[1], sys.argv[2]
text = Path("manifests/guardrails/nemo-config-maas.yaml").read_text()
text = text.replace("MAAS_V1_URL", base).replace("MODEL_ID", model)
parts = []
for doc in text.split("\n---\n"):
    if "kind: Secret" in doc:
        continue
    parts.append(doc)
Path("/tmp/nemo-maas-apply.yaml").write_text("\n---\n".join(parts))
PY
  oc apply -f /tmp/nemo-maas-apply.yaml
  rm -f /tmp/nemo-maas-apply.yaml
else
  echo "=== NemoGuardrails CPU (Presidio + regex) ==="
  oc apply -k manifests/guardrails
fi

echo "Waiting NemoGuardrails/workshop Ready..."
for i in $(seq 1 36); do
  ph=$(oc get nemoguardrails workshop -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  echo "try $i phase=${ph:-?}"
  [[ "$ph" == "Ready" ]] && break
  sleep 8
done
oc get nemoguardrails workshop -n "$NS"
oc get pods,route -n "$NS" | grep -iE 'nemo|workshop' || true
echo
echo "Checks: https://$(oc get route workshop -n ${NS} -o jsonpath='{.status.ingress[0].host}' 2>/dev/null)/v1/guardrail/checks"
