# Kubernetes lab

The manifests are grouped by concern and composed with Kustomize. Every
Kubernetes object has its own YAML file so it can be inspected, changed, and
broken independently.

## Deploy

Preview the fully rendered resources:

```bash
kubectl kustomize kubernetes
```

Apply the complete baseline:

```bash
kubectl apply -k kubernetes
```

Apply one application while experimenting:

```bash
kubectl apply -k kubernetes/apps/frontend/nginx
kubectl apply -k kubernetes/apps/backend/podinfo
kubectl apply -k kubernetes/apps/backend/whoami
kubectl apply -k kubernetes/apps/diagnostics/curl
```

The application-level commands assume the `platform` and `diagnostics`
namespaces already exist. Create them with:

```bash
kubectl apply -k kubernetes/namespaces
```

## Explore

```bash
kubectl get all -n platform
kubectl get all -n diagnostics
kubectl exec -n diagnostics deploy/curl -- curl -sS http://nginx.platform
kubectl exec -n diagnostics deploy/curl -- curl -sS http://podinfo.platform:9898
kubectl exec -n diagnostics deploy/curl -- curl -sS http://whoami.platform
```

The nginx Ingress uses `lab.local` and assumes an ingress controller with the
`nginx` IngressClass is installed. Third-party controller installation belongs
in Helm-based lab setup, not in these application manifests.

## Extend

Add scheduling exercises under `kubernetes/scheduling`, policies under
`kubernetes/policies`, storage exercises under `kubernetes/storage`, and
deliberately broken resources under `kubernetes/failures`. Add each new object
as its own file and include it from the nearest `kustomization.yaml`.
