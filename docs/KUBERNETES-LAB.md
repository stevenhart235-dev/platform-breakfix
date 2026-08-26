# Kubernetes lab

The manifests are grouped by concern and composed with Kustomize. Every
Kubernetes object has its own YAML file so it can be inspected, changed, and
broken independently. `kubernetes/shared` is the provider-independent baseline.
The canonical EKS composition under `providers/aws/eks/kubernetes` adds the
AWS-specific default EBS StorageClass and retains the existing optional Ingress
and extension points.

## Deploy

Preview the fully rendered resources:

```bash
kubectl kustomize kubernetes
```

Apply the complete baseline:

```bash
kubectl apply -k kubernetes
```

The root command remains an EKS-compatible transition entry point. The
equivalent canonical provider command is:

```bash
kubectl apply -k providers/aws/eks/kubernetes
```

Render only the portable baseline with:

```bash
kubectl kustomize kubernetes/shared
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

Add portable scheduling exercises under `kubernetes/scheduling`, policies under
`kubernetes/policies`, and deliberately broken resources under
`kubernetes/failures`. Provider storage configuration belongs under the
provider composition, such as `providers/aws/eks/kubernetes/storage`. Add each
new object as its own file and include it from the nearest `kustomization.yaml`.
