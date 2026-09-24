# Manifests

Kubernetes / OpenShift manifests and helper scripts for the workshop.
Run `oc apply` / scripts from the **repo root**.

| Path | Module |
|---|---|
| `operators/` | Prerequisite operators (module 2), one directory per Operator
| `cluster-monitoring-config.yaml` | User-workload monitoring (module 2) |
| `oauth-htpasswd.yaml` | Optional OAuth htpasswd patch |
| `gatewayclass.yaml` | GatewayClass (module 4) |
| `kuadrant.yaml` | Kuadrant instance (module 4) |
| `rhoai-operator.yaml` | RHOAI Operator |
| `default-dsc.yaml` | DataScienceCluster |
| `odh-dashboard-config-patch.yaml` | Dashboard flags |
| `maas-postgres.yaml` | MaaS Postgres |
| `apply-maas-gateway.sh` | MaaS Gateway |
| `model-catalog-qwen.yaml` | Model Catalog (HF) |
| `fake-gpu-values.yaml` | Fake GPU topology |
| `hardware-profile-cpu.yaml` | CPU hardware profile `cpu-workshop` (module 3)
| `hardware-profile-nvidia.yaml` | GPU profile `nvidia-gpu` (module 5 NVIDIA)
| `fake-gpu-dashboard/` | DCGM Grafana dashboard + ServiceMonitor for Fake GPU (module 5)
| `llminferenceservice-qwen3-06b.yaml` | llm-d CPU + MaaSModelRef |
| `patch-llmisvc-cpu.sh` | Force vLLM CPU after wizard |
| `maas-subscription.yaml` | Auth policy + subscription |
| `fix-maas-authorino-ca.sh` | Authorino + service CA |
| `fix-maas-authorino-grpc-tls.sh` | Authorino gRPC TLS (HTTP 500 en `/maas-api/v1/api-keys`) |
| `apply-gpu-booking-hybrid.sh` | GPU Booking with Fake + real NVIDIA (discovery off) |
| `fix-maas-gpu-utilization.sh` | DCGM → `accelerator_gpu_utilization` on cluster Prometheus + RHOAI MonitoringStack |
| `fix-maas-usage-user-label.sh` | Usage UI user label |
| `fix-playground-maas.sh` | Playground API key + max_tokens |
| `observability/` | Tempo, OTEL, COO, Loki, MinIO (module 11) |
| `apply-maas-observability.sh` | Observability stack installer |
| `evalhub/` | EvalHub + MLflow + Garak/ART providers (modules 12–12.1) |
| `apply-evalhub.sh` | TrustyAI + MLflow + EvalHub |
| `apply-garak.sh` | Enable Garak + `garak-kfp`; `SUBMIT=1` smoke `quick`; `MODE=art` Chatterbox |
| `finops/` | Subscriptions free/team (module 13) |
| `guardrails/` | `NemoGuardrails` CPU (+ MaaS template) (module 14) |
| `apply-guardrails.sh` | TrustyAI + NemoGuardrails (`MODE=maas` opcional) |
| `registry/` | Postgres + ModelRegistry workshop (module 15) |
| `apply-registry.sh` | Model Registry installer |
| `routing/external-model.yaml` | External OpenAI-compatible model (module 16) |
| `pipelines/` | MinIO + DSPA AutoML/AutoRAG (modules 17–18) |
| `apply-pipelines.sh` | Pipeline server |
| `autorag/` | pgvector + vector-stores ConfigMap (module 18) |
| `apply-autorag-store.sh` | Vector store |
| `mcp/` | OpenShift MCPServer + Playground CM (module 20) |
| `apply-mcp.sh` | MCP Lifecycle Operator + server |
| `agents/` | Workshop A2A agent source + deploy (module 21) |
| `apply-agent.sh` | Build (internal registry or QUAY_IMAGE) + deploy |
| `apply-skills.sh` | Console plugin https://github.com/eformat/openshift-skills-plugin |
