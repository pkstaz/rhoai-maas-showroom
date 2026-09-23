#!/usr/bin/env bash
# Wire Gen AI Studio Playground (OGX) to MaaS with a real API key and
# max_tokens=1024 (CPU Qwen max_model_len is 2048; default 4096 fails).
set -euo pipefail

NS="${PLAYGROUND_NS:-llm}"
OGX="${OGX_SERVER:-lsd-genai-playground}"
SUB="${MAAS_SUBSCRIPTION:-qwen-authenticated}"
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="maas.${CLUSTER_DOMAIN}"

echo "Creating API key for subscription=${SUB}..."
RESP=$(curl -sk -X POST "https://${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"playground\",\"subscription\":\"${SUB}\",\"expiresIn\":\"72h\"}")
API_KEY=$(echo "$RESP" | jq -r '.key // empty')
if [[ -z "$API_KEY" || "$API_KEY" == "null" ]]; then
  echo "WARN: subscription ${SUB} failed ($(echo "$RESP" | jq -c .)). Trying demo..."
  SUB=demo
  RESP=$(curl -sk -X POST "https://${MAAS_URL}/maas-api/v1/api-keys" \
    -H "Authorization: Bearer $(oc whoami -t)" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"playground\",\"subscription\":\"${SUB}\",\"expiresIn\":\"72h\"}")
  API_KEY=$(echo "$RESP" | jq -r '.key // empty')
fi
[[ -n "$API_KEY" && "$API_KEY" != "null" ]] || { echo "ERROR: could not create API key"; echo "$RESP"; exit 1; }

oc create secret generic playground-maas-api-key -n "${NS}" \
  --from-literal=api-key="${API_KEY}" --dry-run=client -o yaml | oc apply -f -

echo "Patching OGXServer ${OGX}: VLLM_MAX_TOKENS=1024 + API key..."
export API_KEY
ENV_JSON=$(oc get ogxserver "${OGX}" -n "${NS}" -o json | python3 -c '
import json,sys,os
key=os.environ["API_KEY"]
d=json.load(sys.stdin)
out=[]
for e in d["spec"]["workload"]["overrides"]["env"]:
  n=e["name"]
  if n in ("VLLM_API_TOKEN_1","VLLM_API_TOKEN_2"):
    out.append({"name":n,"value":key})
  elif n in ("VLLM_MAX_TOKENS_1","VLLM_MAX_TOKENS_2"):
    out.append({"name":n,"value":"1024"})
  elif n=="VLLM_TLS_VERIFY":
    out.append({"name":n,"value":"false"})
  else:
    out.append(e)
print(json.dumps({"spec":{"workload":{"overrides":{"env":out}}}}))
')
oc patch ogxserver "${OGX}" -n "${NS}" --type=merge -p "${ENV_JSON}"

# Cap defaults in llama-stack-config (OGX may reset env to 4096)
if oc get cm llama-stack-config -n "${NS}" &>/dev/null; then
  oc get cm llama-stack-config -n "${NS}" -o json | python3 -c '
import json,sys,re
cm=json.load(sys.stdin)
raw=cm["data"]["config.yaml"]
cm["data"]["config.yaml"]=re.sub(r"VLLM_MAX_TOKENS_(\d+):=4096", r"VLLM_MAX_TOKENS_\1:=1024", raw)
for k in ("resourceVersion","uid","creationTimestamp","managedFields","generation"):
  cm["metadata"].pop(k, None)
json.dump(cm, open("/tmp/llama-stack-config-fix.json","w"))
'
  oc replace -f /tmp/llama-stack-config-fix.json
fi

oc get pods -n "${NS}" -o name | grep playground | xargs -r -n1 oc delete -n "${NS}" --force --grace-period=0 2>/dev/null || true

echo "Done. In Gen AI Studio → Playground: New chat, pick the MaaS model, use /no_think."
echo "If max_tokens errors persist, re-run this script (OGX may regenerate env to 4096)."
