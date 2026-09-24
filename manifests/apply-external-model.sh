#!/usr/bin/env bash
# Register a TMM / OpenAI-compatible model as MaaS ExternalModel.
# Instructor values (do not commit): MODEL_NAME, ENDPOINT, API_KEY
# Aliases: TMM_MODEL_NAME, TMM_ENDPOINT, TMM_API_KEY
# Rotate key only: MODE=key API_KEY=... bash manifests/apply-external-model.sh
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DSP_NS="${DSP_NS:-llm}"
MODE="${MODE:-apply}"
PROVIDER="${PROVIDER:-openai}"

MODEL_NAME="${MODEL_NAME:-${TMM_MODEL_NAME:-}}"
ENDPOINT="${ENDPOINT:-${TMM_ENDPOINT:-}}"
API_KEY="${API_KEY:-${TMM_API_KEY:-}}"
TOKENIZER="${TOKENIZER:-${TMM_TOKENIZER:-}}"

# CR / secret / subscription follow the model id (glm-53-flash), not a generic tmm-* name.
k8s_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9.-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}
if [[ -n "${MODEL_NAME}" ]]; then
  CR_NAME="${CR_NAME:-$(k8s_name "${MODEL_NAME}")}"
  SECRET_NAME="${SECRET_NAME:-${CR_NAME}-api-key}"
  SUB_NAME="${SUB_NAME:-${CR_NAME}-authenticated}"
else
  CR_NAME="${CR_NAME:-}"
  SECRET_NAME="${SECRET_NAME:-}"
  SUB_NAME="${SUB_NAME:-}"
fi

if [[ -z "${API_KEY}" ]]; then
  echo "Missing API_KEY (or TMM_API_KEY). The instructor gives a new key each lab."
  exit 1
fi

if [[ "${MODE}" != "key" ]]; then
  if [[ -z "${MODEL_NAME}" || -z "${ENDPOINT}" ]]; then
    echo "Need MODEL_NAME and ENDPOINT (or TMM_* aliases). Example:"
    echo "  export MODEL_NAME='granite-3.3-8b-instruct'"
    echo "  export ENDPOINT='https://maas.apps.tmm.example.com/v1'"
    echo "  export API_KEY='...'"
    echo "  bash manifests/apply-external-model.sh"
    exit 1
  fi
fi

raw="${ENDPOINT}"
raw="${raw#https://}"
raw="${raw#http://}"
FQDN="${raw%%/*}"
FQDN="${FQDN%%:*}"

if [[ "${ENDPOINT}" == http://* || "${ENDPOINT}" == https://* ]]; then
  EVAL_URL="${ENDPOINT%/}"
else
  EVAL_URL="https://${FQDN}/v1"
fi
case "${EVAL_URL}" in
  */v1) ;;
  *) EVAL_URL="${EVAL_URL}/v1" ;;
esac

echo "=== Namespace ${DSP_NS} ==="
oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${DSP_NS}
  labels:
    opendatahub.io/dashboard: "true"
    opendatahub.io/generated-namespace: "true"
    maas.opendatahub.io/gateway-access: "true"
    evalhub.trustyai.opendatahub.io/tenant: "true"
EOF

if [[ -z "${SECRET_NAME}" ]]; then
  echo "Need MODEL_NAME or SECRET_NAME (e.g. glm-53-flash-api-key)"
  exit 1
fi

echo "=== Secret ${SECRET_NAME} (llm + evalhub if present) ==="
for ns in "${DSP_NS}" evalhub; do
  oc get ns "${ns}" >/dev/null 2>&1 || continue
  oc create secret generic "${SECRET_NAME}" -n "${ns}" \
    --from-literal=api-key="${API_KEY}" \
    --from-literal=OPENAI_API_KEY="${API_KEY}" \
    --dry-run=client -o yaml | oc apply -f -
  oc label secret "${SECRET_NAME}" -n "${ns}" \
    inference.llm-d.ai/ipp-managed=true --overwrite >/dev/null
done

if [[ "${MODE}" == "key" ]]; then
  if [[ -z "${SECRET_NAME}" ]]; then
    echo "MODE=key needs SECRET_NAME or MODEL_NAME (e.g. glm-53-flash-api-key)"
    exit 1
  fi
  echo "Updated API key in Secret ${SECRET_NAME}. CR unchanged."
  exit 0
fi

echo "=== Dashboard flag externalModels ==="
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type merge -p '{
  "spec":{"dashboardConfig":{"externalModels":true}}
}' >/dev/null || true

mkdir -p /tmp/rhoai-evalhub
cat >/tmp/rhoai-evalhub/external-model.yaml <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: ExternalModel
metadata:
  name: ${CR_NAME}
  namespace: ${DSP_NS}
  labels:
    opendatahub.io/dashboard: "true"
    opendatahub.io/genai-asset: "true"
spec:
  provider: ${PROVIDER}
  endpoint: ${FQDN}
  targetModel: ${MODEL_NAME}
  credentialRef:
    name: ${SECRET_NAME}
---
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSModelRef
metadata:
  name: ${CR_NAME}
  namespace: ${DSP_NS}
spec:
  modelRef:
    kind: ExternalModel
    name: ${CR_NAME}
---
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: ${SUB_NAME}-access
  namespace: models-as-a-service
  annotations:
    openshift.io/display-name: "${MODEL_NAME} authenticated access"
spec:
  modelRefs:
    - name: ${CR_NAME}
      namespace: ${DSP_NS}
  subjects:
    groups:
      - name: system:authenticated
    users: []
---
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: ${SUB_NAME}
  namespace: models-as-a-service
  annotations:
    openshift.io/display-name: "${MODEL_NAME} authenticated"
spec:
  owner:
    groups:
      - name: system:authenticated
    users: []
  priority: 10
  modelRefs:
    - name: ${CR_NAME}
      namespace: ${DSP_NS}
      tokenRateLimits:
        - limit: 2000
          window: 30s
        - limit: 20000
          window: 5m
EOF

echo "=== Apply ExternalModel + MaaSModelRef + subscription ==="
oc apply -f /tmp/rhoai-evalhub/external-model.yaml

echo "=== Smoke (direct TMM, no local GPU) ==="
code=$(curl -sk -o /tmp/rhoai-evalhub/tmm-models.json -w '%{http_code}' \
  "${EVAL_URL}/models" \
  -H "Authorization: Bearer ${API_KEY}" || true)
echo "GET ${EVAL_URL}/models  HTTP ${code}"
jq -r '.data[]?.id // empty' /tmp/rhoai-evalhub/tmm-models.json 2>/dev/null | head -8 || true

printf '\n'
printf '┌──────────────────────────────────────────────────────────────┐\n'
printf '│  EvalHub / Garak — pegar en el formulario (módulo 12)        │\n'
printf '├──────────────────────────────────────────────────────────────┤\n'
printf '│ MODEL_ID       = %-44s │\n' "${MODEL_NAME}"
printf '│ ENDPOINT       = %-44s │\n' "${EVAL_URL}"
printf '│ API_KEY_SECRET = %-44s │\n' "${SECRET_NAME}"
printf '│ TOKENIZER      = %-44s │\n' "${TOKENIZER:-<pide HF repo al instructor>}"
printf '└──────────────────────────────────────────────────────────────┘\n'
echo
echo "Re-export for later modules:"
echo "  export MODEL_ID='${MODEL_NAME}'"
echo "  export ENDPOINT='${EVAL_URL}'"
echo "  export API_KEY_SECRET='${SECRET_NAME}'"
[[ -n "${TOKENIZER}" ]] && echo "  export TOKENIZER='${TOKENIZER}'"
echo "YAML: /tmp/rhoai-evalhub/external-model.yaml"
echo "Rotate key: MODE=key API_KEY='...' bash manifests/apply-external-model.sh"
