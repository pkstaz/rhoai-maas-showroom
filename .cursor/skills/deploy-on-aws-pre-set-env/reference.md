# Reference — deploy-on-aws-pre-set-env

Read this when executing Authorino uninstall, Kueue recovery, Fake GPU beside NVIDIA, GPU Booking `--no-hooks`, Authorino gRPC TLS, gpt-oss serving, dual MaaS subscriptions, or playground OGX.

## Uninstall standalone Authorino

Authorino must not remain as its own Operator. Connectivity Link (Kuadrant) will install it.

Standalone Authorino on this pre-set cluster is often **AllNamespaces**. OLM copies `authorino-operator.*` CSV into **every** namespace. Deleting only the Subscription in `openshift-operators` is not enough: copies recreate the operator.

```bash
oc get csv -A | grep -iE 'authorino|rhcl|connectivity'
oc get subscription -A | grep -iE 'authorino|rhcl|connectivity'
oc get authorino -A
oc get operators.operators.coreos.com | grep -i authorino || true
```

Delete Authorino CRs first (if any), then OLM objects whose **name is Authorino**, not `rhcl-operator`:

```bash
AUTHORINO_NS=$(oc get subscription -A --no-headers | awk 'tolower($2) ~ /authorino/ {print $1; exit}')
AUTHORINO_SUB=$(oc get subscription -A --no-headers | awk 'tolower($2) ~ /authorino/ {print $2; exit}')

if [ -n "$AUTHORINO_SUB" ]; then
  oc delete authorino --all -A --ignore-not-found
  oc delete subscription "$AUTHORINO_SUB" -n "$AUTHORINO_NS"
  oc delete operators.operators.coreos.com "authorino-operator.${AUTHORINO_NS}" --ignore-not-found
fi

# Wipe CSV copies in every namespace (AllNamespaces leak)
oc get csv -A --no-headers | awk 'tolower($2) ~ /authorino/ {print $1, $2}' \
  | while read -r ns name; do
      oc delete csv "$name" -n "$ns" --ignore-not-found --wait=false
    done

oc get csv -A | grep -i authorino || echo "Authorino operator gone"
```

Do not delete CRDs unless Connectivity Link CSV then fails on CRD ownership. Prefer letting rhcl reconcile Authorino.

Then:

```bash
oc apply -f manifests/operators/connectivity-link/
```

Wait until CSV matching `connectivity` / `rhcl` is `Succeeded`. Authorino CSV returning **via Kuadrant** afterwards is expected.

## Kueue (stable-v1.4 / 1.4.2, AllNamespaces)

`manifests/operators/kueue/subscription.yaml` is already: channel `stable-v1.4`, OperatorGroup `spec: {}`.

- Channel `stable-v1.0` **does not exist** in this catalog. Confirm with:
  ```bash
  oc get packagemanifest kueue-operator -n openshift-marketplace \
    -o jsonpath='default={.status.defaultChannel} channels={.status.channels[*].name}{"\n"}'
  ```
- OwnNamespace / `targetNamespaces: [openshift-kueue-operator]` is **unsupported**. CSV never Succeeds.
- After changing OG or channel, Subscription can stick in `UpgradePending` with **no InstallPlan**. Recover:
  ```bash
  oc delete subscription kueue-operator -n openshift-kueue-operator
  oc apply -f manifests/operators/kueue/
  oc wait csv/kueue-operator.v1.4.2 -n openshift-kueue-operator --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s
  ```
- AllNamespaces copies the Kueue CSV into many namespaces. Success criterion is `kueue-operator.v1.4.2` **Succeeded**, not “only one CSV row”.

## Fake GPU beside NVIDIA GPU Operator

Helm `upgrade -i` of `fake-gpu-operator` 0.2.0 **collides** with ClusterRole `nvidia-device-plugin` owned by the real NVIDIA GPU Operator. Do not take over that ClusterRole.

Always target namespace `gpu-operator` explicitly. Plain `oc apply` without `-n` lands objects in the current project (`my-first-model` while it still exists).

```bash
# After labeling the CPU node and creating ns gpu-operator (module 05-02):
helm pull oci://ghcr.io/run-ai/fake-gpu-operator/fake-gpu-operator --version 0.2.0 --untar --destination /tmp/fake-gpu-chart

helm template gpu-operator /tmp/fake-gpu-chart/fake-gpu-operator \
  -n gpu-operator -f manifests/fake-gpu-values.yaml \
  | awk 'BEGIN{skip=0} /^kind: ClusterRole(Binding)?$/{k=$0} /^  name: nvidia-device-plugin$/{skip=1} /^---$/{skip=0} !skip' \
  | oc apply -n gpu-operator -f -
```

Skip only the **cluster-scoped** `nvidia-device-plugin` Role/Binding. Keep Fake GPU ServiceAccounts, DaemonSets, and namespaced RBAC.

Then pin Fake DaemonSets to the simulated node (otherwise `device-plugin` schedules on the **real** GPU node):

```bash
oc patch ds device-plugin -n gpu-operator --type merge -p '{
  "spec":{"template":{"spec":{"nodeSelector":{"run.ai/simulated-gpu-node-pool":"default"}}}}
}'
oc patch ds nvidia-dcgm-exporter -n gpu-operator --type merge -p '{
  "spec":{"template":{"spec":{"nodeSelector":{"run.ai/simulated-gpu-node-pool":"default"}}}}
}'
oc delete pod -n gpu-operator -l app=device-plugin --ignore-not-found
```

If objects leaked into `my-first-model`, delete Fake GPU DS/Deploy/SA/CM/SVC there (do **not** delete NVIDIA `RuntimeClass` nvidia).

If Fake GPU pods CrashLoop on SCC, grant the Fake GPU SA privileged SCC in `gpu-operator`.

Verify allocatable MIG/H200 **only** on the labeled CPU node, and that the NVIDIA-L4 (or real) node still has its original GPU Operator device plugin.

## GPU Booking (Fake GPU + real NVIDIA)

Upstream discovery is:

```
GET /api/v1/nodes?labelSelector=nvidia.com/gpu.present=true
```

Fake GPU Operator sets `nvidia.com/gpu.present=false` and the status-updater **reverts** `present=true` within seconds (so NVIDIA GPU Operator does not install drivers on the CPU worker). Discover therefore sees only the compact L4.

This lab installs Booking with **discovery off** and a static config that unions:

- nodes with `nvidia.com/gpu.present=true` (real L4)
- nodes with `run.ai/fake.gpu=true` or `run.ai/simulated-gpu-node-pool` (Fake H200 + MIG)

The UI keys cards by `type`. Real and Fake both advertise `nvidia.com/gpu`, so full GPUs are **one** card (count = sum). MIG types from Fake are extra cards.

```bash
bash manifests/apply-gpu-booking-hybrid.sh
```

`--no-hooks` remains mandatory (`ose-cli:latest` ImagePullBackOff). If a previous Helm release hung, `helm uninstall gpu-booking-plugin -n gpu-booking-app-plugin --no-hooks` then re-run the script.

Do not apply GPU Config profile **gb300** (or similar) if you want the lab H200 topology from `manifests/fake-gpu-values.yaml`. The booking script always reads **live** allocatable, so a GB300 profile would show 8 Fake GPUs.

## Authorino gRPC TLS (HTTP 500 on `/maas-api/v1/api-keys`)

Two different Authorino problems:

| Symptom | Cause | Fix |
|---|---|---|
| `/v1/models` or chat `AUTH_FAILURE` / “Exception thrown while generating token” | Authorino cannot trust `maas-api` TLS | `bash manifests/fix-maas-authorino-ca.sh` |
| `POST /maas-api/v1/api-keys` **HTTP 500**; Envoy `kuadrant-auth-service` gRPC not OK | EnvoyFilter `openshift-ai-inference-authn-ssl` makes wasm talk **TLS** to Authorino `:50051`; Authorino listener is **plaintext** | `bash manifests/fix-maas-authorino-grpc-tls.sh` |

Do **not** try to strip TLS with DestinationRule `tls.mode=DISABLE` or EnvoyFilter MERGE → `raw_buffer`. Those lose against `openshift-ai-inference-authn-ssl`. Enable Authorino listener TLS with an OpenShift serving cert, then **delete the MaaS gateway pod** so Envoy reconnects.

Expect HTTP **201** on a new API key. Never print the `key` field in user-facing chat.

## gpt-oss-20b (llm-d, GPU, MaaS, tool calling)

File already exists: `manifests/llminferenceservice-gpt-oss-20b.yaml`.

Use CUDA vLLM (not the CPU image): `registry.redhat.io/rhaii-early-access/vllm-cuda-rhel9:3.5.0-ea.2`.

Pin to the **real** NVIDIA node. Committed selector is `nvidia.com/gpu.product: NVIDIA-L4` (this AWS lab). Confirm:

```bash
oc get nodes -o json | jq -r '.items[] | [
  .metadata.name,
  (.status.allocatable["nvidia.com/gpu"] // "0"),
  (.metadata.labels["nvidia.com/gpu.product"] // "-"),
  (.metadata.labels["node-role.kubernetes.io/master"] // .metadata.labels["node-role.kubernetes.io/control-plane"] // "")
] | @tsv'
```

If product is not `NVIDIA-L4`, patch `spec.template.nodeSelector` (node name or `feature.node.kubernetes.io/pci-10de.present=true`). Never set `run.ai/simulated-gpu-node-pool` on this workload. Compact GPU masters are valid targets.

Apply **in parallel** with Qwen:

```bash
oc apply -f manifests/llminferenceservice-qwen3-06b.yaml
oc apply -f manifests/llminferenceservice-gpt-oss-20b.yaml
oc wait --for=condition=Ready llminferenceservice/qwen3-06b -n llm --timeout=900s
oc wait --for=condition=Ready llminferenceservice/gpt-oss-20b -n llm --timeout=1800s
```

## MaaS subscriptions for both models

```bash
oc apply -f manifests/maas-subscription.yaml
oc apply -f manifests/maas-subscription-gpt-oss-20b.yaml
```

API keys: subscription names `qwen-authenticated` and `gpt-oss-20b-authenticated`.

## Curl smoke

```bash
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
MAAS_URL="maas.${CLUSTER_DOMAIN}"

# Capture keys; do not echo them to the user
Qwen_KEY=$(curl -sk -X POST "https://${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d '{"name":"workshop-qwen","subscription":"qwen-authenticated","expiresIn":"8h"}' | jq -r '.key')

GPT_KEY=$(curl -sk -X POST "https://${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d '{"name":"workshop-gpt","subscription":"gpt-oss-20b-authenticated","expiresIn":"8h"}' | jq -r '.key')

curl -sk "https://${MAAS_URL}/v1/models" -H "Authorization: Bearer ${Qwen_KEY}" | jq '.data[].id'
curl -sk "https://${MAAS_URL}/v1/models" -H "Authorization: Bearer ${GPT_KEY}" | jq '.data[].id'

curl -sk "https://${MAAS_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${Qwen_KEY}" -H "Content-Type: application/json" \
  -d '{"model":"publishers/llm/models/qwen3-06b","messages":[{"role":"user","content":"Say hello in one sentence. /no_think"}],"max_tokens":64}' \
  | jq -r '.choices[0].message.content'

# gpt-oss spends tokens on reasoning; 64 often yields content=None with finish_reason=length
curl -sk "https://${MAAS_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${GPT_KEY}" -H "Content-Type: application/json" \
  -d '{"model":"publishers/llm/models/gpt-oss-20b","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":256}' \
  | jq -r '.choices[0].message.content'
```

If `/v1/models` returns AUTH_FAILURE, re-run `bash manifests/fix-maas-authorino-ca.sh`.
If key creation returns HTTP 500, re-run `bash manifests/fix-maas-authorino-grpc-tls.sh`.

## Playground OGXServer

`bash manifests/fix-playground-maas.sh` needs `ogxservers.ogx.io/lsd-genai-playground` in `llm`. OGX does **not** create that CR until a user opens **Gen AI Studio → Playground** (project `llm`) once.

If `oc get ogxserver -A` is empty: the secret `playground-maas-api-key` may already exist; stop, tell the user to open Playground, then re-run the script. Do not block the rest of the lab (Observability) on this.

If the dashboard regenerates the OGXServer, `VLLM_API_TOKEN=fake` / `VLLM_MAX_TOKENS=4096` come back — re-run the script.

## GPU utilization dashboard (real L4)

RHOAI Observe → *GPU utilization* queries `accelerator_gpu_utilization{exported_namespace,model_name}`. That series is **not** produced by the OTEL collector (it renames DCGM util to `nvidia_gpu_utilization_ratio` and drops it). DCGM **is** on the L4 (`DCGM_FI_DEV_GPU_UTIL`).

```bash
bash manifests/fix-maas-gpu-utilization.sh
```

Creates RHOBS `ServiceMonitor` + `PrometheusRule` (`monitoring.rhobs/v1`, not `monitoring.coreos.com`) in `redhat-ods-monitoring`. The platform Prometheus Operator does not scrape those CRs.

Qwen is CPU → no DCGM join → No data for that model is expected. Filter to gpt-oss or All. Idle L4 is **0%**, not No data; generate chat completions to see a spike. Fake GPU is not scraped (collector only targets `nvidia-gpu-operator`).
