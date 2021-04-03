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

```shell
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
flux bootstrap github --personal --private=false --owner=${MY_GITHUB_USERNAME} --repository="${CLUSTER_NAME}-k8s-clusters" --path=clusters/${CLUSTER_FQDN} --branch=master
```

Output:

```text
► connecting to github.com
✔ repository created
✔ repository cloned
✚ generating manifests
✔ components manifests pushed
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
✔ source-controller: deployment ready
✔ kustomize-controller: deployment ready
✔ helm-controller: deployment ready
✔ notification-controller: deployment ready
✔ install completed
► configuring deploy key
✔ deploy key configured
► generating sync manifests
✔ sync manifests pushed
► applying sync manifests
◎ waiting for cluster sync
✔ bootstrap finished
```

Clone git repository created by flux:

```bash
git clone --quiet "git@github.com:${MY_GITHUB_USERNAME}/${CLUSTER_NAME}-k8s-clusters.git" "tmp/${CLUSTER_FQDN}/${CLUSTER_NAME}-k8s-clusters"
cd tmp/${CLUSTER_FQDN}/${CLUSTER_NAME}-k8s-clusters
```

Create secret with Slack incoming webhook:

```bash
kubectl -n flux-system create secret generic slack-url --from-literal=address=${SLACK_INCOMING_WEBHOOK_URL}
```

### HelmRepository

HelmRepository definitions should be separated from the applications.
The main reason is it's definition in HelmRelease depends on
"namespace". When `HelmRepository` is separated, then you can easily change
namespace for whole application / `HelmRelease`, because the `HelmRepository`
will always be in the `flux-system` namespace.

```yaml
kind: HelmRelease
...
      sourceRef:
        kind: HelmRepository
        name: podinfo
        namespace: flux-system
```

Create `HelmRepository` resource files:

```bash
mkdir -pv apps/base/helmrepository

cat > apps/base/helmrepository/podinfo.yaml << \EOF
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: HelmRepository
metadata:
  name: podinfo
spec:
  interval: 1h
  url: https://stefanprodan.github.io/podinfo
EOF

cat > apps/base/helmrepository/bitnami.yaml << \EOF
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: HelmRepository
metadata:
  name: bitnami
spec:
  interval: 1h
  url: https://charts.bitnami.com/bitnami
EOF

cat > apps/base/helmrepository/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: flux-system
resources:
  - podinfo.yaml
  - bitnami.yaml
EOF

git add apps/base/helmrepository
git commit -m "Add HelmRepository files"
git push
```

### Application configuration

Create Flux configuration for Slack notification + Prometheus monitoring:

```bash
mkdir -pv apps/base/flux

cat > apps/base/flux/provider-slack.yaml << \EOF
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: general
  secretRef:
    name: slack-url
EOF

cat > apps/base/flux/alert-slack.yaml << \EOF
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Alert
metadata:
  name: slack
  namespace: flux-system
spec:
  providerRef:
    name: slack
  eventSeverity: error
  eventSources:
    - kind: GitRepository
      name: "*"
    - kind: Kustomization
      name: "*"
    - kind: HelmRepository
      name: "*"
    - kind: HelmChart
      name: "*"
    - kind: HelmRelease
      name: "*"
EOF

cat > apps/base/flux/monitoring.yaml << \EOF
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: source-controller
  namespace: flux-system
spec:
  namespaceSelector:
    matchNames:
      - flux-system
  selector:
    matchLabels:
      app: source-controller
  podMetricsEndpoints:
  - port: http-prom
EOF

cat > apps/base/flux/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: flux-system
resources:
  - provider-slack.yaml
  - alert-slack.yaml
  - monitoring.yaml
EOF

git add apps/base/flux
git commit -m "Add podmonitor and configure slack notifications to flux"
git push
```

Add podinfo:

```bash
mkdir -pv apps/base/podinfo

cat > apps/base/podinfo/namespace.yaml << \EOF
apiVersion: v1
kind: Namespace
metadata:
  name: podinfo
EOF

cat > apps/base/podinfo/helmrelease.yaml << \EOF
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: podinfo
  namespace: podinfo
spec:
  interval: 1m
  chart:
    spec:
      chart: podinfo
      version: 5.2.0
      sourceRef:
        kind: HelmRepository
        name: podinfo
        namespace: flux-system
EOF

cat > apps/base/podinfo/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrelease.yaml
EOF

git add apps/base/podinfo
git commit -m "Add podinfo"
git push
```

Add Wordpress:

```bash
mkdir -pv apps/base/wordpress

cat > apps/base/wordpress/namespace.yaml << \EOF
apiVersion: v1
kind: Namespace
metadata:
  name: wordpress
EOF

cat > apps/base/wordpress/helmrelease.yaml << \EOF
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: wordpress
  namespace: wordpress
spec:
  interval: 1m
  chart:
    spec:
      chart: wordpress
      version: 10.8.0
      sourceRef:
        kind: HelmRepository
        name: bitnami
        namespace: flux-system
EOF

cat > apps/base/wordpress/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrelease.yaml
EOF

git add apps/base/wordpress
git commit -m "Add wordpress"
git push
```

### Dev group configuration

Add group of applications which belongs to `dev` group of K8s clusters:

```bash
mkdir -pv apps/dev

cat > apps/dev/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
commonLabels:
  group: dev
resources:
  - ../base/flux
  - ../base/helmrepository
  - ../base/podinfo
  - ../base/wordpress
patchesStrategicMerge:
  - flux-values.yaml
  - podinfo-values.yaml
  - wordpress-values.yaml
EOF

cat > apps/dev/flux-values.yaml << \EOF
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  channel: ${slack_channel}
EOF

cat > apps/dev/podinfo-values.yaml << \EOF
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: podinfo
  namespace: podinfo
spec:
  chart:
    spec:
      version: 5.2.0
  values:
  values:
    serviceMonitor:
      enabled: true
    ui:
      color: "#577c34"
      message: "Environment: dev | Cluster: ${cluster_fqdn} | Certificate: ${letsencrypt_environment:=staging}"
    ingress:
      enabled: true
      path: /
      hosts:
        - ${podinfo_dns_name}.${cluster_fqdn}
      tls:
        - secretName: ingress-cert-${letsencrypt_environment:=staging}
          hosts:
            - ${podinfo_dns_name}.${cluster_fqdn}
EOF

cat > apps/dev/wordpress-values.yaml << \EOF
# https://github.com/bitnami/charts/blob/master/bitnami/wordpress/values.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: wordpress
  namespace: wordpress
spec:
  values:
    wordpressUsername: admin
    wordpressPassword: ${wordpress_password}
    wordpressEmail: ${wordpress_email}
    wordpressSkipInstall: false
    service:
      type: ClusterIP
    ingress:
      enabled: true
      hostname: ${wordpress_hostname}
      annotations:
        nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${cluster_fqdn}/oauth2/auth
        nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${cluster_fqdn}/oauth2/start?rd=\$scheme://\$host\$request_uri
      extraTls:
        - hosts:
            - ${wordpress_hostname}
          secretName: ingress-cert-${letsencrypt_environment:=staging}
    persistence:
      enabled: false
    # metrics:
    #   enabled: true
    serviceMonitor:
      enabled: true
    mariadb:
      auth:
        rootPassword: ${wordpress_password}
        password: ${wordpress_password}
      primary:
        persistence:
          enabled: false
EOF

git add apps/dev
git commit -m "Add dev group"
git push
```

### Cluster apps configuration

Configure cluster applications and their variables:

```bash
cat > clusters/${CLUSTER_FQDN}/apps.yaml << EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1beta1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 1m
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  validation: client
  path: ./apps/dev
  postBuild:
    substitute:
      cluster_fqdn: "${CLUSTER_FQDN}"
      letsencrypt_environment: "${LETSENCRYPT_ENVIRONMENT}"
      podinfo_dns_name: flux-dev-podinfo
      slack_channel: ${SLACK_CHANNEL}
      wordpress_password: ${MY_PASSWORD}
      wordpress_email: ${MY_EMAIL}
      wordpress_hostname: flux-dev-wordpress.${CLUSTER_FQDN}
EOF

git add clusters/${CLUSTER_FQDN}
git commit -m "Configure cluster applications"
git push
```

Check the flux errors:

```bash
flux logs --level=error --all-namespaces
```
