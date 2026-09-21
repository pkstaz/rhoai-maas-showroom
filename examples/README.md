# YAML de apoyo del workshop

Ejecuta los `oc apply` desde la raíz del repo.

| Archivo | Módulo |
|---|---|
| `oauth-htpasswd.yaml` | Patch OAuth htpasswd (opcional; el lab usa `oc patch`) |
| `subscriptions.yaml` | Operadores previos |
| `gatewayclass.yaml` | Gateway API (antes de Kuadrant) |
| `kuadrant.yaml` | Connectivity Link |
| `rhoai-operator.yaml` | Operator RHOAI |
| `default-dsc.yaml` | DataScienceCluster |
| `odh-dashboard-config-patch.yaml` | Flags del dashboard (mejor usar `oc patch`) |
| `maas-postgres.yaml` | Postgres MaaS |
| `apply-maas-gateway.sh` | Gateway MaaS |
| `model-catalog-qwen.yaml` | Catalog HF |
| `llminferenceservice-qwen3-06b.yaml` | llm-d CPU + MaaSModelRef |
| `maas-subscription.yaml` | Auth policy + subscription |
