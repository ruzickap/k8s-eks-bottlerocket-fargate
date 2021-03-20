# GitOps tools

## ArgoCD

Set the `ARGOCD_ADMIN_PASSWORD` with password:

```bash
ARGOCD_ADMIN_PASSWORD=$(htpasswd -nbBC 10 "" ${MY_PASSWORD} | tr -d ":\n" | sed "s/\$2y/\$2a/")
```

Install `argo-cd`
[helm chart](https://artifacthub.io/packages/helm/argo/argo-cd)
and modify the
[default values](https://github.com/argoproj/argo-helm/blob/master/charts/argo-cd/values.yaml).

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install --version 2.11.3 --namespace argocd --create-namespace --values - argocd argo/argo-cd << EOF
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
dex:
  enabled: false
server:
  extraArgs:
    - --insecure
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
  ingress:
    enabled: true
    hosts:
      - argocd.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - argocd.${CLUSTER_FQDN}
  config:
    url: https://argocd.${CLUSTER_FQDN}
    # OIDC does not work for self signed certs: https://github.com/argoproj/argo-cd/issues/4344
    oidc.config: |
      name: Dex
      issuer: https://dex.${CLUSTER_FQDN}
      clientID: argocd.${CLUSTER_FQDN}
      clientSecret: ${MY_PASSWORD}
      requestedIDTokenClaims:
        groups:
          essential: true
      requestedScopes:
        - openid
        - profile
        - email
  rbacConfig:
    policy.default: role:admin
repoServer:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
configs:
  secret:
    argocdServerAdminPassword: ${ARGOCD_ADMIN_PASSWORD}
EOF
```

Output:

```text
"argo" has been added to your repositories
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
NAME: argocd
LAST DEPLOYED: Thu Dec 10 16:02:58 2020
NAMESPACE: argocd
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
In order to access the server UI you have the following options:

1. kubectl port-forward service/argocd-server -n argocd 8080:443

    and then open the browser on http://localhost:8080 and accept the certificate

2. enable ingress in the values file `service.ingress.enabled` and either
      - Add the annotation for ssl passthrough: https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/ingress.md#option-1-ssl-passthrough
      - Add the `--insecure` flag to `server.extraArgs` in the values file and terminate SSL at your ingress: https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/ingress.md#option-2-multiple-ingress-objects-and-hosts


After reaching the UI the first time you can login with username: admin and the password will be the
name of the server pod. You can get the pod name by running:

kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2
```

## Flux

Make sure you have the `GITHUB_TOKEN` configured properly.

Install Flux on a Kubernetes cluster and configure it to manage itself from
a Git repository:

```bash
flux bootstrap github --owner=ruzickap --repository="${CLUSTER_FQDN}" --path=clusters/${CLUSTER_FQDN} --branch=master --personal
```

Output:

```text
► connecting to github.com
✔ repository created
✔ repository cloned
✚ generating manifests
✔ components manifests pushed
I0320 10:36:05.631729   56136 request.go:655] Throttling request took 2.251906176s, request: GET:https://A30F2A05E6BCE8B011E3B68F8AC4B68B.gr7.eu-central-1.eks.amazonaws.com/apis/vpcresources.k8s.aws/v1beta1?timeout=32s
► installing components in flux-system namespace
namespace/flux-system created
customresourcedefinition.apiextensions.k8s.io/alerts.notification.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/buckets.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/gitrepositories.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/helmcharts.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/helmreleases.helm.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/helmrepositories.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/kustomizations.kustomize.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/providers.notification.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/receivers.notification.toolkit.fluxcd.io created
serviceaccount/helm-controller created
serviceaccount/kustomize-controller created
serviceaccount/notification-controller created
serviceaccount/source-controller created
clusterrole.rbac.authorization.k8s.io/crd-controller-flux-system created
clusterrolebinding.rbac.authorization.k8s.io/cluster-reconciler-flux-system created
clusterrolebinding.rbac.authorization.k8s.io/crd-controller-flux-system created
service/notification-controller created
service/source-controller created
service/webhook-receiver created
deployment.apps/helm-controller created
deployment.apps/kustomize-controller created
deployment.apps/notification-controller created
deployment.apps/source-controller created
networkpolicy.networking.k8s.io/allow-scraping created
networkpolicy.networking.k8s.io/allow-webhooks created
networkpolicy.networking.k8s.io/deny-ingress created
◎ verifying installation
✔ kustomize-controller: deployment ready
✔ helm-controller: deployment ready
✔ notification-controller: deployment ready
✔ source-controller: deployment ready
✔ install completed
► configuring deploy key
✔ deploy key configured
► generating sync manifests
✔ sync manifests pushed
► applying sync manifests
◎ waiting for cluster sync
✔ bootstrap finished
```
