# YAML de apoyo del workshop

Ejecuta los `oc apply` desde la raíz del repo.

| Archivo | Módulo |
|---|---|
| `oauth-htpasswd.yaml` | Patch OAuth htpasswd (opcional; el lab usa `oc patch`) |
| `subscriptions.yaml` | Operadores previos (incluye Connectivity Link) |
| `gatewayclass.yaml` | GatewayClass (módulo 4) |
| `kuadrant.yaml` | Instancia Kuadrant (módulo 4) |
| `rhoai-operator.yaml` | Operator RHOAI |
| `default-dsc.yaml` | DataScienceCluster |
| `odh-dashboard-config-patch.yaml` | Flags del dashboard (mejor usar `oc patch`) |
| `maas-postgres.yaml` | Postgres MaaS |
| `apply-maas-gateway.sh` | Gateway MaaS |
| `model-catalog-qwen.yaml` | Catalog HF |
| `fake-gpu-values.yaml` | Fake GPU: 1× H200 141GB + slices MIG |
| `hardware-profiles.yaml` | Perfiles `cpu-workshop`, `fake-h200`, `fake-h200-mig` |
| `llminferenceservice-qwen3-06b.yaml` | llm-d CPU + MaaSModelRef |
| `patch-llmisvc-cpu.sh` | Parche wizard → vLLM CPU |
| `maas-subscription.yaml` | Auth policy + subscription |
| `observability/` | Tempo, OTEL, COO, Loki, MinIO (módulo 11) |
| `apply-maas-observability.sh` | Instala stack observabilidad MaaS |
| `evalhub/` | Postgres + EvalHub CR (módulo 12) |
| `apply-evalhub.sh` | TrustyAI Managed + EvalHub lab |
