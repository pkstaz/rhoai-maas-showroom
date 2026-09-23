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
| `hardware-profiles.yaml` | Hardware profiles |
| `llminferenceservice-qwen3-06b.yaml` | llm-d CPU + MaaSModelRef |
| `patch-llmisvc-cpu.sh` | Force vLLM CPU after wizard |
| `maas-subscription.yaml` | Auth policy + subscription |
| `fix-maas-authorino-ca.sh` | Authorino + service CA |
| `fix-maas-usage-user-label.sh` | Usage UI user label |
| `fix-playground-maas.sh` | Playground API key + max_tokens |
| `observability/` | Tempo, OTEL, COO, Loki, MinIO (module 11) |
| `apply-maas-observability.sh` | Observability stack installer |
| `evalhub/` | EvalHub + MLflow (module 12) |
| `apply-evalhub.sh` | TrustyAI + MLflow + EvalHub |
