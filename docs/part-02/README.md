# K8s tools

Install the basic tools, before running some applications like monitoring
([Prometheus](https://prometheus.io)), DNS integration
([external-dns](https://github.com/kubernetes-sigs/external-dns)), Ingress ([ingress-nginx](https://kubernetes.github.io/ingress-nginx/))
or certificate management ([cert-manager](https://cert-manager.io/)).

## kube-prometheus-stack

Create Grafana secret with Google OAuth 2.0 Client IDs:

```bash
MY_GOOGLE_OAUTH_CLIENT_ID_BASE64=$(echo -n "${MY_GOOGLE_OAUTH_CLIENT_ID}" | base64 -w 0)
MY_GOOGLE_OAUTH_CLIENT_SECRET_BASE64=$(echo -n "${MY_GOOGLE_OAUTH_CLIENT_SECRET}" | base64 -w 0)

kubectl create namespace kube-prometheus-stack
kubectl apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-env
  namespace: kube-prometheus-stack
type: Opaque
data:
  GF_AUTH_GENERIC_OAUTH_CLIENT_ID: ${MY_GOOGLE_OAUTH_CLIENT_ID_BASE64}
  GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: ${MY_GOOGLE_OAUTH_CLIENT_SECRET_BASE64}
EOF
```

Create config file for `kube-prometheus-stack` Helm chart:

```bash
helm repo add --force-update prometheus-community https://prometheus-community.github.io/helm-charts ; helm repo update > /dev/null
helm install --version 11.1.1 --namespace kube-prometheus-stack --create-namespace --values - kube-prometheus-stack prometheus-community/kube-prometheus-stack << EOF
# https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml
defaultRules:
  rules:
    etcd: false
    kubernetesSystem: false
    kubeScheduler: false

alertmanager:
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://auth.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://auth.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - alertmanager.${CLUSTER_FQDN}
    paths:
      - /
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - alertmanager.${CLUSTER_FQDN}
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: gp2
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 1Gi
    externalUrl: https://alertmanager.${CLUSTER_FQDN}

# https://github.com/grafana/helm-charts/blob/main/charts/grafana/values.yaml
grafana:
  ingress:
    enabled: true
    hosts:
      - grafana.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - grafana.${CLUSTER_FQDN}
  sidecar:
    dashboards:
      enabled: true
  env:
    GF_SERVER_ROOT_URL: "https://grafana.${CLUSTER_FQDN}"
    GF_ANALYTICS_REPORTING_ENABLED: "false"
    GF_AUTH_DISABLE_LOGIN_FORM: "true"
    GF_USERS_ALLOW_SIGN_UP: "false"
    GF_USERS_AUTO_ASSIGN_ORG_ROLE: "Admin"
    GF_SMTP_ENABLED: "false"
    GF_AUTH_GENERIC_OAUTH_ENABLED: "true"
    GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP: "true"
    GF_AUTH_GENERIC_OAUTH_NAME: "Google"
    GF_AUTH_GENERIC_OAUTH_SCOPES: "https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email"
    GF_AUTH_GENERIC_OAUTH_AUTH_URL: "https://accounts.google.com/o/oauth2/auth"
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL: "https://accounts.google.com/o/oauth2/token"
    GF_AUTH_GENERIC_OAUTH_API_URL: "https://www.googleapis.com/oauth2/v1/userinfo"
  envFromSecret: grafana-env
  plugins:
    - grafana-piechart-panel
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: "default"
          orgId: 1
          folder: ""
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      # https://grafana.com/grafana/dashboards/8685
      k8s-cluster-summary:
        gnetId: 8685
        revision: 1
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/1860
      node-exporter-full:
        gnetId: 1860
        revision: 21
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/3662
      prometheus-2-0-overview:
        gnetId: 3662
        revision: 2
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/9852
      stians-disk-graphs:
        gnetId: 9852
        revision: 1
        datasource: Prometheus

kubeControllerManager:
  enabled: false
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
prometheusOperator:
  tls:
    enabled: false
  admissionWebhooks:
    enabled: false

prometheus:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://auth.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://auth.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    enabled: true
    hosts:
      - prometheus.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - prometheus.${CLUSTER_FQDN}
  prometheusSpec:
    externalUrl: https://prometheus.${CLUSTER_FQDN}
    ruleSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    retentionSize: 1GB
    serviceMonitorSelectorNilUsesHelmValues: false
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp2
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
EOF
```

Output:

```text
"prometheus-community" has been added to your repositories
NAME: kube-prometheus-stack
LAST DEPLOYED: Fri Nov 13 16:45:33 2020
NAMESPACE: kube-prometheus-stack
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace kube-prometheus-stack get pods -l "release=kube-prometheus-stack"

Visit https://github.com/prometheus-operator/kube-prometheus for instructions on how to create & configure Alertmanager and Prometheus instances using the Operator.
```

## cert-manager

Install `cert-manager` and use the previously created Role ARN to annotate
service account:

```bash
ROUTE53_ROLE_ARN=$(eksctl get iamserviceaccount --region eu-central-1 --cluster=${CLUSTER_NAME} --namespace cert-manager -o json  | jq -r ".iam.serviceAccounts[] | select(.metadata.name==\"cert-manager\") .status.roleARN")

helm repo add --force-update jetstack https://charts.jetstack.io ; helm repo update > /dev/null
helm install --version v1.0.3 --namespace cert-manager --create-namespace --wait --values - cert-manager jetstack/cert-manager << EOF
installCRDs: true
prometheus:
  servicemonitor:
    enabled: true
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${ROUTE53_ROLE_ARN}
extraArgs:
  - --enable-certificate-owner-ref=true
securityContext:
  enabled: true
EOF
```

Output:

```text
"jetstack" has been added to your repositories
NAME: cert-manager
LAST DEPLOYED: Fri Nov 13 16:45:46 2020
NAMESPACE: cert-manager
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
cert-manager has been deployed successfully!

In order to begin issuing certificates, you will need to set up a ClusterIssuer
or Issuer resource (for example, by creating a 'letsencrypt-staging' issuer).

More information on the different types of issuers and how to configure them
can be found in our documentation:

https://cert-manager.io/docs/configuration/

For information on how to configure cert-manager to automatically provision
Certificates for Ingress resources, take a look at the `ingress-shim`
documentation:

https://cert-manager.io/docs/usage/ingress/
```

Add ClusterIssuers for Let's Encrypt staging and production:

```bash
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging-dns
  namespace: cert-manager
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${MY_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging-dns
    solvers:
      - selector:
          dnsZones:
            - ${CLUSTER_FQDN}
        dns01:
          route53:
            region: eu-central-1
---
# Create ClusterIssuer for production to get real signed certificates
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production-dns
  namespace: cert-manager
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${MY_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-production-dns
    solvers:
      - selector:
          dnsZones:
            - ${CLUSTER_FQDN}
        dns01:
          route53:
            region: eu-central-1
EOF
```

Create wildcard certificate using `cert-manager`:

```bash
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
  namespace: cert-manager
spec:
  secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
  issuerRef:
    name: letsencrypt-${LETSENCRYPT_ENVIRONMENT}-dns
    kind: ClusterIssuer
  commonName: "*.${CLUSTER_FQDN}"
  dnsNames:
    - "*.${CLUSTER_FQDN}"
    - "${CLUSTER_FQDN}"
EOF
```

## external-dns

Install `external-dns`:

```bash
ROUTE53_ROLE_ARN=$(eksctl get iamserviceaccount --region eu-central-1 --cluster=${CLUSTER_NAME} --namespace external-dns -o json  | jq -r ".iam.serviceAccounts[] | select(.metadata.name==\"external-dns\") .status.roleARN")

helm repo add --force-update bitnami https://charts.bitnami.com/bitnami ; helm repo update > /dev/null
helm install --version 3.5.1 --namespace external-dns --create-namespace --values - external-dns bitnami/external-dns << EOF
# https://github.com/bitnami/charts/blob/master/bitnami/external-dns/values.yaml
aws:
  region: eu-central-1
domainFilters:
  - ${CLUSTER_FQDN}
interval: 10s
policy: sync
replicas: 1
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${ROUTE53_ROLE_ARN}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
  runAsNonRoot: true
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
EOF
```

Output:

```text
"bitnami" has been added to your repositories
NAME: external-dns
LAST DEPLOYED: Fri Nov 13 16:46:25 2020
NAMESPACE: external-dns
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
** Please be patient while the chart is being deployed **

To verify that external-dns has started, run:

  kubectl --namespace=external-dns get pods -l "app.kubernetes.io/name=external-dns,app.kubernetes.io/instance=external-dns"
```

## kubed

Install `kubed` - tool which helps the certificate secretes to be copied to
the namespaces.

See the details:

* [https://cert-manager.io/docs/faq/kubed/](https://cert-manager.io/docs/faq/kubed/)
* [https://appscode.com/products/kubed/v0.12.0/guides/config-syncer/intra-cluster/](https://appscode.com/products/kubed/v0.12.0/guides/config-syncer/intra-cluster/)

```bash
helm repo add --force-update appscode https://charts.appscode.com/stable/ ; helm repo update > /dev/null
helm install --version v0.12.0 --namespace kubed --create-namespace kubed appscode/kubed \
  --set config.clusterName="${CLUSTER_FQDN}"
```

Output:

```text
"appscode" has been added to your repositories
NAME: kubed
LAST DEPLOYED: Fri Nov 13 16:46:34 2020
NAMESPACE: kubed
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
To verify that Kubed has started, run:

  kubectl get deployment --namespace kubed -l "app.kubernetes.io/name=kubed,app.kubernetes.io/instance=kubed"
```

Annotate the wildcard certificate secret. It will allow `kubed` to distribute
it to all namespaces.

```bash
kubectl wait --timeout=5m --namespace cert-manager --for=condition=Ready certificate "ingress-cert-${LETSENCRYPT_ENVIRONMENT}"
kubectl annotate secret "ingress-cert-${LETSENCRYPT_ENVIRONMENT}" -n cert-manager kubed.appscode.com/sync=""
```

## ingress-nginx

Install the Ingress:

```bash
helm repo add --force-update ingress-nginx https://kubernetes.github.io/ingress-nginx ; helm repo update > /dev/null
helm install --version 3.7.1 --namespace ingress-nginx --create-namespace --wait --values - ingress-nginx ingress-nginx/ingress-nginx << EOF
# https://github.com/kubernetes/ingress-nginx/blob/master/charts/ingress-nginx/values.yaml
controller:
  extraArgs:
    default-ssl-certificate: cert-manager/ingress-cert-${LETSENCRYPT_ENVIRONMENT}
  replicaCount: 1
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
EOF
```

Output:

```text
"ingress-nginx" has been added to your repositories
NAME: ingress-nginx
LAST DEPLOYED: Fri Nov 13 16:50:45 2020
NAMESPACE: ingress-nginx
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The ingress-nginx controller has been installed.
It may take a few minutes for the LoadBalancer IP to be available.
You can watch the status by running 'kubectl --namespace ingress-nginx get services -o wide -w ingress-nginx-controller'

An example Ingress that makes use of the controller:

  apiVersion: networking.k8s.io/v1beta1
  kind: Ingress
  metadata:
    annotations:
      kubernetes.io/ingress.class: nginx
    name: example
    namespace: foo
  spec:
    rules:
      - host: www.example.com
        http:
          paths:
            - backend:
                serviceName: exampleService
                servicePort: 80
              path: /
    # This section is only required if TLS is to be enabled for the Ingress
    tls:
        - hosts:
            - www.example.com
          secretName: example-tls

If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

  apiVersion: v1
  kind: Secret
  metadata:
    name: example-tls
    namespace: foo
  data:
    tls.crt: <base64 encoded cert>
    tls.key: <base64 encoded key>
  type: kubernetes.io/tls
```

## oauth2-proxy

Install [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) to secure
the endpoints like (`prometheus.`, `alertmanager.`).

```bash
kubectl create namespace oauth2-proxy
helm repo add --force-update stable https://charts.helm.sh/stable ; helm repo update > /dev/null
helm install --version 3.2.3 --namespace oauth2-proxy --create-namespace --values - oauth2-proxy stable/oauth2-proxy << EOF
# https://github.com/helm/charts/blob/master/stable/oauth2-proxy/values.yaml
config:
  clientID: "${MY_GOOGLE_OAUTH_CLIENT_ID}"
  clientSecret: "${MY_GOOGLE_OAUTH_CLIENT_SECRET}"
  cookieSecret: "$(openssl rand -base64 32 | head -c 32 | base64 )"
  configFile: |-
    email_domains = [ "*" ]
    upstreams = [ "file:///dev/null" ]
    whitelist_domains = ".${CLUSTER_FQDN}"
    cookie_domain = ".${CLUSTER_FQDN}"
authenticatedEmailsFile:
  enabled: true
  restricted_access: |-
    ${MY_EMAIL}
ingress:
  enabled: true
  hosts:
    - auth.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - auth.${CLUSTER_FQDN}
EOF
```

Output:

```text
namespace/oauth2-proxy created
"stable" has been added to your repositories
NAME: oauth2-proxy
LAST DEPLOYED: Fri Nov 13 16:51:49 2020
NAMESPACE: oauth2-proxy
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
To verify that oauth2-proxy has started, run:

  kubectl --namespace=oauth2-proxy get pods -l "app=oauth2-proxy"
```

## Gangway

```bash
helm install --version 0.4.3 --namespace gangway --create-namespace --values - gangway stable/gangway << EOF
gangway:
  clusterName: ${CLUSTER_FQDN}
  authorizeUrl: https://accounts.google.com/o/oauth2/auth
  tokenUrl: https://accounts.google.com/o/oauth2/token
  audience: ${MY_GOOGLE_OAUTH_CLIENT_ID}
  scopes: ["openid", "profile", "email"]
  redirectUrl: https://${CLUSTER_FQDN}/callback
  clientId: ${MY_GOOGLE_OAUTH_CLIENT_ID}
  clientSecret: ${MY_GOOGLE_OAUTH_CLIENT_SECRET}
  apiServerURL: $(awk "/server:/ { print \$2 }" "${KUBECONFIG}")
ingress:
  enabled: true
  hosts:
    - ${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - ${CLUSTER_FQDN}
EOF
```

Output:

```text
NAME: gangway
LAST DEPLOYED: Fri Nov 13 16:51:53 2020
NAMESPACE: gangway
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
1. Get the application URL by running these commands:
  https://k1.k8s.mylabs.dev/
```

## cluster-autoscaler

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install --version 1.1.0 --namespace kube-system --values - cluster-autoscaler autoscaler/cluster-autoscaler-chart << EOF
autoDiscovery:
  clusterName: ${CLUSTER_NAME}
awsRegion: eu-central-1
serviceMonitor:
  enabled: true
  namespace: kube-prometheus-stack
EOF
```

Output:

```text
"autoscaler" has been added to your repositories
NAME: cluster-autoscaler
LAST DEPLOYED: Fri Nov 13 16:51:58 2020
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
To verify that cluster-autoscaler has started, run:

  kubectl --namespace=kube-system get pods -l "app.kubernetes.io/name=aws-cluster-autoscaler-chart,app.kubernetes.io/instance=cluster-autoscaler"
```

## metrics-server

Enable Horizontal Pod Autoscaler by installing `metrics-server`:

```bash
helm install --version 2.11.2 --namespace kube-system metrics-server stable/metrics-server
```

Output:

```text
NAME: metrics-server
LAST DEPLOYED: Fri Nov 13 16:52:02 2020
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
NOTES:
The metric server has been deployed.

In a few minutes you should be able to list metrics using the following
command:

  kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes"
```

## HashiCorp Vault

Install HashiCorp Vault:

```bash
kubectl create namespace vault
helm repo add --force-update hashicorp https://helm.releases.hashicorp.com ; helm repo update > /dev/null
# https://github.com/hashicorp/vault-helm/blob/master/values.yaml
helm install --version 0.8.0 --namespace vault --values - vault hashicorp/vault << EOF
injector:
  metrics:
    enabled: false
server:
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://auth.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://auth.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - host: vault.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - vault.${CLUSTER_FQDN}
  dataStorage:
    size: 1Gi
EOF
```

Output:

```text
namespace/vault created
"hashicorp" has been added to your repositories
NAME: vault
LAST DEPLOYED: Fri Nov 13 16:52:16 2020
NAMESPACE: vault
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Thank you for installing HashiCorp Vault!

Now that you have deployed Vault, you should look over the docs on using
Vault with Kubernetes available here:

https://www.vaultproject.io/docs/


Your release is named vault. To learn more about the release, try:

  $ helm status vault
  $ helm get manifest vault
```
