#!/usr/bin/env bash
# Enable Garak + ART (garak-kfp / Chatterbox intents) on the workshop EvalHub.
# Does not submit a scan unless SUBMIT=1 (quick) or MODE=art SUBMIT=1.
# Usage:
#   bash manifests/apply-garak.sh
#   SUBMIT=1 bash manifests/apply-garak.sh
#   MODE=art bash manifests/apply-garak.sh
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DSP_NS="${DSP_NS:-llm}"
MODE="${MODE:-quick}"
SUBMIT="${SUBMIT:-0}"

if ! oc get evalhub evalhub -n evalhub >/dev/null 2>&1; then
  echo "EvalHub missing — run bash manifests/apply-evalhub.sh first"
  exit 1
fi

echo "=== Providers: lm-evaluation-harness + garak + garak-kfp ==="
oc patch evalhub evalhub -n evalhub --type=merge -p '{
  "spec": {
    "providers": ["lm-evaluation-harness", "garak", "garak-kfp"]
  }
}'

echo "Waiting EvalHub rollout..."
oc rollout status deploy -n evalhub -l app=eval-hub --timeout=180s 2>/dev/null || \
  oc get pods -n evalhub --no-headers | head -8

EVALHUB_HOST=$(oc get route -n evalhub -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
if [[ -z "${EVALHUB_HOST}" ]]; then
  echo "WARN: no Route in evalhub yet"
  EVALHUB_URL="https://evalhub.evalhub.svc.cluster.local:8443"
else
  EVALHUB_URL="https://${EVALHUB_HOST}"
fi
TOKEN=$(oc whoami -t)
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"

echo
echo "EvalHub: ${EVALHUB_URL}"
echo "Listing providers (X-Tenant=${DSP_NS})..."
curl -sk "${EVALHUB_URL}/api/v1/evaluations/providers?benchmarks=true" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Tenant: ${DSP_NS}" | jq -r '
    (.items // .)[]? |
    [.resource.id // .id // .name, (.title // .name // ""), ((.benchmarks // []) | length)] |
    @tsv
  ' 2>/dev/null || true

echo
echo "Garak benchmarks:"
curl -sk "${EVALHUB_URL}/api/v1/evaluations/providers/garak" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Tenant: ${DSP_NS}" | jq -r '
    (.benchmarks // [])[]? | "  \(.id)\t\(.name // "")"
  ' 2>/dev/null || echo "  (list after the pod restarts — hard-refresh Evaluations)"

# Prefer instructor external model secret (module 8.3), then Qwen lab key.
API_KEY_SECRET="${API_KEY_SECRET:-}"
if [[ -z "${API_KEY_SECRET}" ]]; then
  if oc get secret glm-53-flash-api-key -n "${DSP_NS}" >/dev/null 2>&1; then
    API_KEY_SECRET="glm-53-flash-api-key"
  elif oc get secret tmm-api-key -n "${DSP_NS}" >/dev/null 2>&1; then
    API_KEY_SECRET="tmm-api-key"
  else
    API_KEY_SECRET="maas-eval-api-key"
  fi
fi
if [[ -z "${MODEL_ID:-}" ]]; then
  if [[ "${API_KEY_SECRET}" == "glm-53-flash-api-key" || "${API_KEY_SECRET}" == "tmm-api-key" ]]; then
    MODEL_ID="${MODEL_NAME:-${TMM_MODEL_NAME:-glm-53-flash}}"
    ENDPOINT="${ENDPOINT:-${TMM_ENDPOINT:-}}"
  elif oc get secret "${API_KEY_SECRET}" -n "${DSP_NS}" >/dev/null 2>&1; then
    KEY=$(oc get secret "${API_KEY_SECRET}" -n "${DSP_NS}" -o jsonpath='{.data.OPENAI_API_KEY}' | base64 -d)
    MODEL_ID=$(curl -sk "${MAAS_URL}/v1/models" -H "Authorization: Bearer ${KEY}" | jq -r '.data[0].id // empty')
  fi
fi
MODEL_ID="${MODEL_ID:-publishers/llm/models/qwen3-06b}"
ENDPOINT="${ENDPOINT:-${MAAS_URL}/v1}"

QUICK_JSON=$(mktemp)
cat >"${QUICK_JSON}" <<EOF
{
  "name": "garak-quick-qwen",
  "model": {
    "url": "${ENDPOINT}",
    "name": "${MODEL_ID}",
    "auth": { "secret_ref": "${API_KEY_SECRET}" }
  },
  "benchmarks": [
    {
      "id": "quick",
      "provider_id": "garak",
      "parameters": { "execution_mode": "simple" }
    }
  ],
  "experiment": { "name": "qwen-redteam" }
}
EOF

ART_JSON=$(mktemp)
cat >"${ART_JSON}" <<EOF
{
  "name": "intents-scan-lab",
  "model": {
    "url": "${ENDPOINT}",
    "name": "${MODEL_ID}",
    "auth": { "secret_ref": "${API_KEY_SECRET}" }
  },
  "benchmarks": [
    {
      "id": "intents",
      "provider_id": "garak-kfp",
      "parameters": {
        "kfp_config": {
          "endpoint": "https://ds-pipeline-dspa.${DSP_NS}.svc.cluster.local:8443",
          "namespace": "${DSP_NS}",
          "s3_secret_name": "pipeline-minio",
          "s3_endpoint": "http://pipeline-minio.${DSP_NS}.svc.cluster.local:9000",
          "s3_bucket": "mlpipeline",
          "verify_ssl": false
        },
        "intents_models": {
          "judge": { "url": "${ENDPOINT}", "name": "${MODEL_ID}" },
          "sdg": { "url": "${ENDPOINT}", "name": "hosted_vllm/${MODEL_ID}" }
        },
        "garak_config": {
          "run": { "generations": 1, "langproviders": null },
          "plugins": {
            "probe_spec": ["spo.SPOIntent"]
          }
        }
      }
    }
  ],
  "experiment": { "name": "qwen-redteam" }
}
EOF

echo
echo "Smoke Garak (CPU, profile quick). Secret ${API_KEY_SECRET} must exist in llm *and* evalhub."
echo "  curl -sk -X POST ${EVALHUB_URL}/api/v1/evaluations/jobs \\"
echo "    -H 'Authorization: Bearer \$(oc whoami -t)' -H 'X-Tenant: ${DSP_NS}' \\"
echo "    -H 'Content-Type: application/json' -d @${QUICK_JSON}"
echo
echo "ART / Chatterbox (garak-kfp intents) needs module 17 DSPA. Lab trims TAP/translation."
echo "  MODE=art SUBMIT=1 bash manifests/apply-garak.sh"

submit_job() {
  local file="$1"
  echo "Submitting $(basename "${file}") ..."
  curl -sk -X POST "${EVALHUB_URL}/api/v1/evaluations/jobs" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Tenant: ${DSP_NS}" \
    -H "Content-Type: application/json" \
    -d @"${file}" | jq .
}

if [[ "${SUBMIT}" == "1" ]]; then
  if [[ "${MODE}" == "art" ]]; then
    oc get dspa dspa -n "${DSP_NS}" >/dev/null
    # kube-rbac-proxy on ds-pipeline returns 401 unless the EvalHub job SA
    # can call datasciencepipelinesapplications/api.
    oc -n "${DSP_NS}" create rolebinding evalhub-dspa-user-access \
      --role=ds-pipeline-user-access-dspa \
      --serviceaccount="${DSP_NS}:evalhub-evalhub-job" \
      --dry-run=client -o yaml | oc apply -f -
    submit_job "${ART_JSON}"
  else
    submit_job "${QUICK_JSON}"
  fi
  echo "UI: Develop & train → Evaluations (project ${DSP_NS})"
fi

# Keep payloads for copy/paste
mkdir -p /tmp/rhoai-evalhub
cp "${QUICK_JSON}" /tmp/rhoai-evalhub/garak-quick.json
cp "${ART_JSON}" /tmp/rhoai-evalhub/intents-scan.json
echo "JSON: /tmp/rhoai-evalhub/garak-quick.json  /tmp/rhoai-evalhub/intents-scan.json"
echo "UI: Evaluations → Start evaluation run → provider Garak → Quick"
