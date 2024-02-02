# GitOps tools

## ArgoCD

Set the `ARGOCD_ADMIN_PASSWORD` with password:

```bash
ARGOCD_ADMIN_PASSWORD=$(htpasswd -nbBC 10 "" "${MY_PASSWORD}" | tr -d ":\n" | sed "s/\$2y/\$2a/")
```

Install `argo-cd`
[helm chart](https://artifacthub.io/packages/helm/argo/argo-cd)
and modify the
[default values](https://github.com/argoproj/argo-helm/blob/master/charts/argo-cd/values.yaml).

```bash
helm repo add --force-update argo https://argoproj.github.io/argo-helm
helm upgrade --install --version 3.12.1 --namespace argocd --create-namespace --values - argocd argo/argo-cd << EOF
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

Handy repositories:

* [Helm Users! What Flux 2 Can Do For You](https://github.com/kingdonb/kccnceu2021)
* [flux2-multi-tenancy](https://github.com/fluxcd/flux2-multi-tenancy)
* [https://github.com/relu/flux-demo](https://github.com/relu/flux-demo)

Make sure you have the `GITHUB_TOKEN` configured properly.

Install Flux on a Kubernetes cluster and configure it to manage itself from
a Git repository:

```bash
flux bootstrap github --personal --owner="${MY_GITHUB_USERNAME}" --repository="${CLUSTER_NAME}-k8s-clusters" --path="clusters/${CLUSTER_FQDN}" --branch=master
```

Output:

```text
► connecting to github.com
✔ repository "https://github.com/ruzickap/kube1-k8s-clusters" created
► cloning branch "master" from Git repository "https://github.com/ruzickap/kube1-k8s-clusters.git"
✔ cloned repository
► generating component manifests
✔ generated component manifests
✔ committed sync manifests to "master" ("14d6ae5fca7dc2edceaa224958ecf6876d4307af")
► pushing component manifests to "https://github.com/ruzickap/kube1-k8s-clusters.git"
✔ installed components
✔ reconciled components
► determining if source secret "flux-system/flux-system" exists
► generating source secret
✔ public key: ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBChRlBEwVkTuaBocgPHeCLvRIG8hjfC91/VUVmKqiIGoj69lW09r8kC+TIi5TSKRq/A3Pl2PNxc/tnI4T2EMn7QPSs6wJYrcMP4DMs/BUKLFKASSDz5ovcX+8JPhHYvfWw==
✔ configured deploy key "flux-system-master-flux-system-./clusters/kube1.k8s.mylabs.dev" for "https://github.com/ruzickap/kube1-k8s-clusters"
► applying source secret "flux-system/flux-system"
✔ reconciled source secret
► generating sync manifests
✔ generated sync manifests
✔ committed sync manifests to "master" ("32b36ef8b2b80c8fb97ca5fb7edf5ffd5c7bab4c")
► pushing sync manifests to "https://github.com/ruzickap/kube1-k8s-clusters.git"
► applying sync manifests
✔ reconciled sync configuration
◎ waiting for Kustomization "flux-system/flux-system" to be reconciled
✔ Kustomization reconciled successfully
► confirming components are healthy
✔ helm-controller: deployment ready
✔ kustomize-controller: deployment ready
✔ notification-controller: deployment ready
✔ source-controller: deployment ready
✔ all components are healthy
```

Create GPG key in `tmp/${CLUSTER_FQDN}/.gnupg` directory:

```bash
export GNUPGHOME="${PWD}/tmp/${CLUSTER_FQDN}/.gnupg"
mkdir -vp "${GNUPGHOME}" && chmod 0700 "${GNUPGHOME}"

cat > "${GNUPGHOME}/my_gpg_key" << EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Comment: Flux secrets
Name-Real: ${CLUSTER_FQDN}
Name-Email: ${MY_EMAIL}
Expire-Date: 0
%no-protection
%commit
EOF

gpg --verbose --batch --gen-key "${GNUPGHOME}/my_gpg_key"
```

Output

```text
mkdir: created directory '/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/tmp/kube1.k8s.mylabs.dev/.gnupg'
gpg: Note: RFC4880bis features are enabled.
gpg: keybox '/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/tmp/kube1.k8s.mylabs.dev/.gnupg/pubring.kbx' created
gpg: no running gpg-agent - starting '/usr/local/Cellar/gnupg/2.3.3_1/bin/gpg-agent'
gpg: waiting for the agent to come up ... (5s)
gpg: connection to the agent established
gpg: writing self signature
gpg: RSA/SHA256 signature from: "D2FAC1BD98CDE147 [?]"
gpg: writing key binding signature
gpg: RSA/SHA256 signature from: "D2FAC1BD98CDE147 [?]"
gpg: RSA/SHA256 signature from: "6259C1389B0D69B6 [?]"
gpg: writing public key to '/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/tmp/kube1.k8s.mylabs.dev/.gnupg/pubring.kbx'
gpg: /Users/ruzickap/git/k8s-eks-bottlerocket-fargate/tmp/kube1.k8s.mylabs.dev/.gnupg/trustdb.gpg: trustdb created
gpg: using pgp trust model
gpg: key D2FAC1BD98CDE147 marked as ultimately trusted
gpg: directory '/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/tmp/kube1.k8s.mylabs.dev/.gnupg/openpgp-revocs.d' created
gpg: writing to '/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/tmp/kube1.k8s.mylabs.dev/.gnupg/openpgp-revocs.d/8407817AB5F5627156F3EDA5D2FAC1BD98CDE147.rev'
gpg: RSA/SHA256 signature from: "D2FAC1BD98CDE147 kube1.k8s.mylabs.dev (Flux secrets) <petr.ruzicka@gmail.com>"
gpg: revocation certificate stored as '/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/tmp/kube1.k8s.mylabs.dev/.gnupg/openpgp-revocs.d/8407817AB5F5627156F3EDA5D2FAC1BD98CDE147.rev'
```

Store the key fingerprint as an environment variable:

```bash
KEY_FP=$(gpg --list-secret-keys --with-colons "${CLUSTER_FQDN}" | awk -F: "NR == 2 { print \$10 }")
export KEY_FP
```

Output:

```text
gpg: checking the trustdb
gpg: marginals needed: 3  completes needed: 1  trust model: pgp
gpg: depth: 0  valid:   1  signed:   0  trust: 0-, 0q, 0n, 0m, 0f, 1u
```

Export the public and private keypair from your local GPG keyring and create
a Kubernetes secret named `sops-gpg` in the `flux-system` namespace:

```bash
gpg --export-secret-keys --armor "${KEY_FP}" |
  kubectl create secret generic sops-gpg \
    --namespace=flux-system --from-file=sops.asc=/dev/stdin \
    --save-config --dry-run=client -o yaml |
  kubectl apply -f -
```

Configure Git:

```bash
grep -q "github.com" ~/.ssh/known_hosts || ssh-keyscan github.com >> ~/.ssh/known_hosts 2> /dev/null
test -f ~/.gitconfig || git config --global user.email "${MY_EMAIL}"
```

Clone git repository created by flux:

```bash
test -d "tmp/${CLUSTER_FQDN}/${CLUSTER_NAME}-k8s-clusters" || git clone --quiet "https://${GITHUB_TOKEN}@github.com/${MY_GITHUB_USERNAME}/${CLUSTER_NAME}-k8s-clusters.git" "tmp/${CLUSTER_FQDN}/${CLUSTER_NAME}-k8s-clusters"
cd "tmp/${CLUSTER_FQDN}/${CLUSTER_NAME}-k8s-clusters" || exit
```

Export the public key into the Git directory

```bash
gpg --export --armor "${KEY_FP}" > "clusters/${CLUSTER_FQDN}/.sops.pub.asc"
git add "clusters/${CLUSTER_FQDN}/.sops.pub.asc"
git commit -m "Share GPG public key for secrets generation" || true
```

Configure the Git directory for encryption:

```bash
cat > "clusters/${CLUSTER_FQDN}/.sops.yaml" << EOF
creation_rules:
  - path_regex: .*.yaml
    encrypted_regex: ^(data|stringData)$
    pgp: ${KEY_FP}
EOF

git add "clusters/${CLUSTER_FQDN}/.sops.yaml"
git commit -m "Configure the Git directory for encryption" || true
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
git commit -m "Add HelmRepository files" || true
```

### Application configuration

#### Flux configuration

Create Flux configuration for Slack notification + Prometheus monitoring.

Providers needs to be configured/installed before the alerts - that is the
reason why I'm doing the `Kustomization` which contains `dependsOn`.

```bash
mkdir -pv apps/base/flux/{providers,alerts}

cat > apps/base/flux/providers/provider-slack.yaml << \EOF
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: ${slack_channel}
  secretRef:
    name: slack-url
EOF

cat > apps/base/flux/providers/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: flux-system
resources:
  - provider-slack.yaml
EOF

cat > apps/base/flux/providers.yaml << EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1beta1
kind: Kustomization
metadata:
  name: providers
  namespace: flux-system
spec:
  interval: 1m
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/base/flux/providers/
  postBuild:
    substitute:
      slack_channel: general
EOF

cat > apps/base/flux/alerts/alert-slack.yaml << \EOF
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

cat > apps/base/flux/alerts/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: flux-system
resources:
  - alert-slack.yaml
EOF

cat > apps/base/flux/alerts.yaml << EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1beta1
kind: Kustomization
metadata:
  name: alerts
  namespace: flux-system
spec:
  dependsOn:
    - name: providers
  interval: 1m
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/base/flux/alerts/
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

cat > apps/base/flux/github-receiver.yaml << \EOF
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Receiver
metadata:
  name: github-receiver
  namespace: flux-system
spec:
  type: github
  events:
    - "ping"
    - "push"
  secretRef:
    name: github-webhook-token
  resources:
    - kind: GitRepository
      name: flux-system
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: flux-receiver
  namespace: flux-system
EOF

cat > apps/base/flux/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: flux-system
resources:
  - alerts.yaml
  - github-receiver.yaml
  - monitoring.yaml
  - providers.yaml
EOF

git add apps/base/flux
git commit -m "Add podmonitor and configure slack notifications for flux" || true
```

#### podinfo

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
# https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml
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
      # Version can be overwritten by values specified in apps/{dev,stage,prod}/podinfo-values.yaml
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
git commit -m "Add podinfo" || true
```

#### WordPress

Add WordPress:

```bash
mkdir -pv apps/base/wordpress

cat > apps/base/wordpress/helmrelease.yaml << \EOF
# https://github.com/bitnami/charts/blob/master/bitnami/wordpress/values.yaml
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
      # Version should be overwritten ba values specified in apps/{dev,stage,prod}/wordpress-values.yaml
      version: 10.8.0
      sourceRef:
        kind: HelmRepository
        name: bitnami
        namespace: flux-system
  values:
    wordpressSkipInstall: false
    service:
      type: ClusterIP
    persistence:
      enabled: false
    metrics:
      enabled: true
    serviceMonitor:
      enabled: true
    mariadb:
      primary:
        persistence:
          enabled: false
EOF

cat > apps/base/wordpress/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
EOF

git add apps/base/wordpress
git commit -m "Add wordpress" || true
```

### Dev group configuration

Add group of applications which belongs to `dev` group of K8s clusters:

```bash
mkdir -pv apps/dev/helmrepository

cat > apps/dev/helmrepository/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base/helmrepository
EOF

cat > apps/dev/kustomization.yaml << \EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base/flux
  - ../base/podinfo
  - ../base/wordpress
patchesStrategicMerge:
  - flux-values.yaml
  - podinfo-values.yaml
  - wordpress-values.yaml
EOF

cat > apps/dev/flux-values.yaml << \EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1beta1
kind: Kustomization
metadata:
  name: providers
  namespace: flux-system
spec:
  postBuild:
    substitute:
      slack_channel: ${slack_channel}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: flux-receiver
  namespace: flux-system
spec:
  rules:
  - host: flux-receiver.${cluster_fqdn}
    http:
      paths:
      - path: /
        pathType: ImplementationSpecific
        backend:
          service:
            name: webhook-receiver
            port:
              name: http
  tls:
  - hosts:
    - flux-receiver.${cluster_fqdn}
    secretName: flux-receiver.${cluster_fqdn}
EOF

cat > apps/dev/podinfo-values.yaml << \EOF
# https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: podinfo
  namespace: podinfo
spec:
  chart:
    spec:
      version: 5.1.0
  values:
    serviceMonitor:
      enabled: true
    ui:
      color: "#577c34"
      message: "Environment: dev | Hostname: ${podinfo_hostname} | Certificate: ${letsencrypt_environment:=staging}"
    ingress:
      enabled: true
      path: /
      hosts:
      - ${podinfo_hostname}
      tls:
      - secretName: ingress-cert-${letsencrypt_environment:=staging}
        hosts:
        - ${podinfo_hostname}
EOF

cat > apps/dev/wordpress-values.yaml << \EOF
# https://github.com/bitnami/charts/blob/master/bitnami/wordpress/values.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: wordpress
  namespace: wordpress
spec:
  chart:
    spec:
      version: 10.7.0
  values:
    wordpressUsername: admin
    existingSecret: wordpress-password
    wordpressEmail: ${wordpress_email}
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
    mariadb:
      auth:
        existingSecret: mariadb-auth-secret
EOF

git add apps/dev
git commit -m "Add dev group" || true
```

### Cluster apps configuration

Configure cluster applications and their variables:

```bash
cat > "clusters/${CLUSTER_FQDN}/local.yaml" << EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1beta1
kind: Kustomization
metadata:
  name: local
  namespace: flux-system
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-gpg
  interval: 10m
  path: ./clusters/${CLUSTER_FQDN}/local
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
EOF

# This customization is needed to force flux to work with specific
# files/directories and not go to "unwanted" directories
# (like local without proper SOPS confoguration)
cat > "clusters/${CLUSTER_FQDN}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- flux-system
- local.yaml
EOF

mkdir -pv "clusters/${CLUSTER_FQDN}/local"
cat > "clusters/${CLUSTER_FQDN}/local/helmrepository.yaml" << EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1beta1
kind: Kustomization
metadata:
  name: helmrepository-dev
  namespace: flux-system
spec:
  interval: 1m
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  validation: client
  path: ./apps/dev/helmrepository
EOF

cat > "clusters/${CLUSTER_FQDN}/local/apps.yaml" << EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1beta1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  dependsOn:
    - name: helmrepository-dev
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
      podinfo_hostname: flux-dev-podinfo.${CLUSTER_FQDN}
      slack_channel: ${SLACK_CHANNEL}
      wordpress_email: ${MY_EMAIL}
      wordpress_hostname: flux-dev-wordpress.${CLUSTER_FQDN}
EOF

# Namespaces needs to be created before the flux+sops will decrypt the secrets
# `secret-wordpress-password.yaml` into it
cat > "clusters/${CLUSTER_FQDN}/local/namespace-wordpress.yaml" << \EOF
apiVersion: v1
kind: Namespace
metadata:
  name: wordpress
EOF

kubectl create secret generic wordpress-password --namespace wordpress --from-literal=wordpress-password="${MY_PASSWORD}" --dry-run=client -o yaml > "clusters/${CLUSTER_FQDN}/local/secret-wordpress-password.yaml"
sops --encrypt --in-place --config "clusters/${CLUSTER_FQDN}/.sops.yaml" "clusters/${CLUSTER_FQDN}/local/secret-wordpress-password.yaml"

kubectl create secret generic mariadb-auth-secret --namespace wordpress --from-literal=mariadb-root-password="${MY_PASSWORD}" --from-literal=mariadb-password="${MY_PASSWORD}" --dry-run=client -o yaml > "clusters/${CLUSTER_FQDN}/local/secret-mariadb-auth.yaml"
sops --encrypt --in-place --config "clusters/${CLUSTER_FQDN}/.sops.yaml" "clusters/${CLUSTER_FQDN}/local/secret-mariadb-auth.yaml"

kubectl -n flux-system create secret generic slack-url --from-literal=address="${SLACK_INCOMING_WEBHOOK_URL}" --dry-run=client -o yaml > "clusters/${CLUSTER_FQDN}/local/secret-slack-url.yaml"
sops --encrypt --in-place --config "clusters/${CLUSTER_FQDN}/.sops.yaml" "clusters/${CLUSTER_FQDN}/local/secret-slack-url.yaml"

GITHUB_WEBHOOK_SECRET=$(head -c 12 /dev/urandom | shasum | cut -d " " -f1)
kubectl -n flux-system create secret generic github-webhook-token --from-literal=token="${GITHUB_WEBHOOK_SECRET}" --dry-run=client -o yaml > "clusters/${CLUSTER_FQDN}/local/secret-github-webhook-token.yaml"
sops --encrypt --in-place --config "clusters/${CLUSTER_FQDN}/.sops.yaml" "clusters/${CLUSTER_FQDN}/local/secret-github-webhook-token.yaml"

cat > "clusters/${CLUSTER_FQDN}/local/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- apps.yaml
- helmrepository.yaml
- namespace-wordpress.yaml
- secret-mariadb-auth.yaml
- secret-slack-url.yaml
- secret-github-webhook-token.yaml
- secret-wordpress-password.yaml
EOF

git add "clusters/${CLUSTER_FQDN}"
git commit -m "Configure cluster applications" || true
git push && flux reconcile source git flux-system
```

Output:

```text
[master 1546a95] Configure cluster applications
 10 files changed, 232 insertions(+)
 create mode 100644 clusters/kube1.k8s.mylabs.dev/kustomization.yaml
 create mode 100644 clusters/kube1.k8s.mylabs.dev/local.yaml
 create mode 100644 clusters/kube1.k8s.mylabs.dev/local/apps.yaml
 create mode 100644 clusters/kube1.k8s.mylabs.dev/local/helmrepository.yaml
 create mode 100644 clusters/kube1.k8s.mylabs.dev/local/kustomization.yaml
 create mode 100644 clusters/kube1.k8s.mylabs.dev/local/namespace-wordpress.yaml
 create mode 100644 clusters/kube1.k8s.mylabs.dev/local/secret-github-webhook-token.yaml
 create mode 100644 clusters/kube1.k8s.mylabs.dev/local/secret-mariadb-auth.yaml
 create mode 100644 clusters/kube1.k8s.mylabs.dev/local/secret-slack-url.yaml
 create mode 100644 clusters/kube1.k8s.mylabs.dev/local/secret-wordpress-password.yaml
Enumerating objects: 77, done.
Counting objects: 100% (77/77), done.
Delta compression using up to 8 threads
Compressing objects: 100% (63/63), done.
Writing objects: 100% (74/74), 16.79 KiB | 781.00 KiB/s, done.
Total 74 (delta 13), reused 0 (delta 0), pack-reused 0
remote: Resolving deltas: 100% (13/13), done.
To https://github.com/ruzickap/kube1-k8s-clusters.git
   32b36ef..1546a95  master -> master
► annotating GitRepository flux-system in flux-system namespace
✔ GitRepository annotated
◎ waiting for GitRepository reconciliation
✔ fetched revision master/1546a9590214db9fea0ed9e033d98f6ef8966798
```

Configure GitHub Webhook:

```bash
sleep 100
FLUX_RECEIVER_URL=$(kubectl -n flux-system get receiver github-receiver -o jsonpath="{.status.url}")
curl -s -H "Authorization: token $GITHUB_TOKEN" -X POST -d "{\"active\": true, \"events\": [\"push\"], \"config\": {\"url\": \"https://flux-receiver.${CLUSTER_FQDN}${FLUX_RECEIVER_URL}\", \"content_type\": \"json\", \"secret\": \"${GITHUB_WEBHOOK_SECRET}\", \"insecure_ssl\": \"1\"}}" "https://api.github.com/repos/${MY_GITHUB_USERNAME}/${CLUSTER_NAME}-k8s-clusters/hooks" | jq
```

Output:

```json
{
  "type": "Repository",
  "id": 330855597,
  "name": "web",
  "active": true,
  "events": [
    "push"
  ],
  "config": {
    "content_type": "json",
    "insecure_ssl": "1",
    "secret": "********",
    "url": "https://flux-receiver.kube1.k8s.mylabs.dev/hook/42efc6e2c884da9a1d63a24a75a4147f3291935455523b4cb5d2857fba62c09e"
  },
  "updated_at": "2021-11-29T18:40:43Z",
  "created_at": "2021-11-29T18:40:43Z",
  "url": "https://api.github.com/repos/ruzickap/kube1-k8s-clusters/hooks/330855597",
  "test_url": "https://api.github.com/repos/ruzickap/kube1-k8s-clusters/hooks/330855597/test",
  "ping_url": "https://api.github.com/repos/ruzickap/kube1-k8s-clusters/hooks/330855597/pings",
  "deliveries_url": "https://api.github.com/repos/ruzickap/kube1-k8s-clusters/hooks/330855597/deliveries",
  "last_response": {
    "code": null,
    "status": "unused",
    "message": null
  }
}
```

Check the flux errors:

```bash
flux logs --level=error --all-namespaces
```

Check Kustomization, Helmreleases and Helmrepositories:

```bash
kubectl get kustomizations,helmreleases,helmrepository -A
```

Output:

```text
NAMESPACE     NAME                                                           READY   STATUS                                                              AGE
flux-system   kustomization.kustomize.toolkit.fluxcd.io/alerts               True    Applied revision: master/1546a9590214db9fea0ed9e033d98f6ef8966798   56m
flux-system   kustomization.kustomize.toolkit.fluxcd.io/apps                 True    Applied revision: master/1546a9590214db9fea0ed9e033d98f6ef8966798   56m
flux-system   kustomization.kustomize.toolkit.fluxcd.io/flux-system          True    Applied revision: master/1546a9590214db9fea0ed9e033d98f6ef8966798   57m
flux-system   kustomization.kustomize.toolkit.fluxcd.io/helmrepository-dev   True    Applied revision: master/1546a9590214db9fea0ed9e033d98f6ef8966798   56m
flux-system   kustomization.kustomize.toolkit.fluxcd.io/local                True    Applied revision: master/1546a9590214db9fea0ed9e033d98f6ef8966798   56m
flux-system   kustomization.kustomize.toolkit.fluxcd.io/providers            True    Applied revision: master/1546a9590214db9fea0ed9e033d98f6ef8966798   56m

NAMESPACE   NAME                                           READY   STATUS                             AGE
podinfo     helmrelease.helm.toolkit.fluxcd.io/podinfo     True    Release reconciliation succeeded   56m
wordpress   helmrelease.helm.toolkit.fluxcd.io/wordpress   True    Release reconciliation succeeded   56m

NAMESPACE     NAME                                              URL                                      READY   STATUS                                                                               AGE
flux-system   helmrepository.source.toolkit.fluxcd.io/bitnami   https://charts.bitnami.com/bitnami       True    Fetched revision: 1092b3963ba377fc4151cf6bff76e9a095868cc2394ac59c9faa815b0c6b172e   56m
flux-system   helmrepository.source.toolkit.fluxcd.io/podinfo   https://stefanprodan.github.io/podinfo   True    Fetched revision: 83a3c595163a6ff0333e0154c790383b5be441b9db632cb36da11db1c4ece111   56m
```
