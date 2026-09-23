# Prerequisite operators

One directory per Operator subscription (Namespace / OperatorGroup / Subscription as needed).

Apply from the repo root, waiting for CSV `Succeeded` between each:

```bash
oc apply -f manifests/operators/cert-manager/
oc apply -f manifests/operators/pipelines/
oc apply -f manifests/operators/connectivity-link/
oc apply -f manifests/operators/leader-worker-set/
oc apply -f manifests/operators/kueue/
```
