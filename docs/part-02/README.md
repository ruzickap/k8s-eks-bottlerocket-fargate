# K8s tools

Install the basic tools, before running some applications like monitoring
([Prometheus](https://prometheus.io)), DNS integration
([external-dns](https://github.com/kubernetes-sigs/external-dns)), Ingress ([ingress-nginx](https://kubernetes.github.io/ingress-nginx/)),
certificate management ([cert-manager](https://cert-manager.io/)), ...

## aws-ebs-csi-driver

```bash
EBS_CONTROLLER_ROLE_ARN=$(eksctl get iamserviceaccount --cluster=${CLUSTER_NAME} --namespace kube-system -o json  | jq -r ".iam.serviceAccounts[] | select(.metadata.name==\"ebs-csi-controller-sa\") .status.roleARN")
EBS_SNAPSHOT_ROLE_ARN=$(eksctl get iamserviceaccount --cluster=${CLUSTER_NAME} --namespace kube-system -o json  | jq -r ".iam.serviceAccounts[] | select(.metadata.name==\"ebs-snapshot-controller\") .status.roleARN")
```

Install Amazon EBS CSI Driver `aws-ebs-csi-driver`
[helm chart](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/tree/master/charts/aws-ebs-csi-driver)
and modify the
[default values](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/charts/aws-ebs-csi-driver/values.yaml):

```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm install --version 0.7.0 --namespace kube-system --values - aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver << EOF
enableVolumeScheduling: true
enableVolumeResizing: true
enableVolumeSnapshot: false
k8sTagClusterId: ${CLUSTER_FQDN}
serviceAccount:
  controller:
    annotations:
      eks.amazonaws.com/role-arn: ${EBS_CONTROLLER_ROLE_ARN}
  snapshot:
    annotations:
      eks.amazonaws.com/role-arn: ${EBS_SNAPSHOT_ROLE_ARN}
EOF
```

Delete default `gp2` storage class:

```bash
kubectl delete storageclass gp2
```

Create new `gp3` storage class using `aws-ebs-csi-driver`:

```bash
kubectl apply -f - << EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: gp3
provisioner: ebs.csi.aws.com # Amazon EBS CSI driver
parameters:
  type: gp3
  encrypted: "true" # EBS volumes will always be encrypted by default
reclaimPolicy: Delete
EOF
```

## aws-for-fluent-bit

Install `aws-for-fluent-bit`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-for-fluent-bit)
and modify the
[default values](https://github.com/aws/eks-charts/blob/master/stable/aws-for-fluent-bit/values.yaml).

```bash
helm repo add eks https://aws.github.io/eks-charts
helm install --version 0.1.5 --namespace kube-system --values - aws-for-fluent-bit eks/aws-for-fluent-bit << EOF
cloudWatch:
  region: ${AWS_DEFAULT_REGION}
  logGroupName: /aws/eks/${CLUSTER_FQDN}/logs
firehose:
  enabled: false
kinesis:
  enabled: false
elasticsearch:
  enabled: false
EOF
```

The `aws-for-fluent-bit` will create Log group `/aws/eks/k1.k8s.mylabs.dev/logs`
and stream the logs from all pods there.

## aws-cloudwatch-metrics

Install `aws-cloudwatch-metrics`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-cloudwatch-metrics)
and modify the
[default values](https://github.com/aws/eks-charts/blob/master/stable/aws-cloudwatch-metrics/values.yaml).

```bash
helm install --version 0.0.1 --namespace amazon-cloudwatch --create-namespace --values - aws-cloudwatch-metrics eks/aws-cloudwatch-metrics << EOF
clusterName: ${CLUSTER_FQDN}
EOF
```

The `aws-cloudwatch-metrics` populates "Container insights" in CloudWatch

## kube-prometheus-stack

Install `kube-prometheus-stack`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml):

```bash
helm repo add --force-update prometheus-community https://prometheus-community.github.io/helm-charts ; helm repo update > /dev/null
helm install --version 12.7.0 --namespace kube-prometheus-stack --create-namespace --values - kube-prometheus-stack prometheus-community/kube-prometheus-stack << EOF
defaultRules:
  rules:
    etcd: false
    kubernetesSystem: false
    kubeScheduler: false

alertmanager:
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - alertmanager.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - alertmanager.${CLUSTER_FQDN}
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 1Gi

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
  grafana.ini:
    server:
      root_url: https://grafana.${CLUSTER_FQDN}
    auth.basic:
      disable_login_form: true
    auth.generic_oauth:
      name: Dex
      enabled: true
      allow_sign_up: true
      scopes: openid profile email groups
      auth_url: https://dex.${CLUSTER_FQDN}/auth
      token_url: https://dex.${CLUSTER_FQDN}/token
      api_url: https://dex.${CLUSTER_FQDN}/userinfo
      client_id: grafana.${CLUSTER_FQDN}
      client_secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
      tls_skip_verify_insecure: true
    users:
      auto_assign_org_role: Admin

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
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
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
          storageClassName: gp3
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
LAST DEPLOYED: Thu Dec 10 15:56:10 2020
NAMESPACE: kube-prometheus-stack
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace kube-prometheus-stack get pods -l "release=kube-prometheus-stack"

Visit https://github.com/prometheus-operator/kube-prometheus for instructions on how to create & configure Alertmanager and Prometheus instances using the Operator.
```

## cert-manager

Install `cert-manager`
[helm chart](https://artifacthub.io/packages/helm/jetstack/cert-manager)
and modify the
[default values](https://github.com/jetstack/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml).
The the previously created Role ARN will be used to annotate service account.

```bash
ROUTE53_ROLE_ARN_CERT_MANAGER=$(eksctl get iamserviceaccount --cluster=${CLUSTER_NAME} --namespace cert-manager -o json  | jq -r ".iam.serviceAccounts[] | select(.metadata.name==\"cert-manager\") .status.roleARN")

helm repo add --force-update jetstack https://charts.jetstack.io ; helm repo update > /dev/null
helm install --version v1.1.0 --namespace cert-manager --create-namespace --wait --values - cert-manager jetstack/cert-manager << EOF
# https://github.com/jetstack/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml
installCRDs: true
prometheus:
  servicemonitor:
    enabled: true
image:
  pullPolicy: Always
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${ROUTE53_ROLE_ARN_CERT_MANAGER}
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
LAST DEPLOYED: Thu Dec 10 15:56:33 2020
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
            region: ${AWS_DEFAULT_REGION}
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
            region: ${AWS_DEFAULT_REGION}
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

Install `external-dns`
[helm chart](https://artifacthub.io/packages/helm/bitnami/external-dns)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/external-dns/values.yaml).
`external-dns` will take care about DNS records.
(`ROUTE53_ROLE_ARN` variable was defined before for `cert-manager`)

```bash
ROUTE53_ROLE_ARN_EXTERNAL_DNS=$(eksctl get iamserviceaccount --cluster=${CLUSTER_NAME} --namespace external-dns -o json  | jq -r ".iam.serviceAccounts[] | select(.metadata.name==\"external-dns\") .status.roleARN")
```

```bash
helm repo add --force-update bitnami https://charts.bitnami.com/bitnami ; helm repo update > /dev/null
helm install --version 4.4.1 --namespace external-dns --create-namespace --values - external-dns bitnami/external-dns << EOF
image:
  pullPolicy: Always
aws:
  region: ${AWS_DEFAULT_REGION}
domainFilters:
  - ${CLUSTER_FQDN}
interval: 10s
policy: sync
replicas: 1
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${ROUTE53_ROLE_ARN_EXTERNAL_DNS}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
  runAsNonRoot: true
resources:
  limits:
    cpu: 50m
    memory: 50Mi
  requests:
    memory: 50Mi
    cpu: 10m
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
LAST DEPLOYED: Thu Dec 10 15:57:16 2020
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

`kubed` - tool which helps with copying the certificate secretes across the
namespaces.

See the details:

* [https://cert-manager.io/docs/faq/kubed/](https://cert-manager.io/docs/faq/kubed/)
* [https://appscode.com/products/kubed/v0.12.0/guides/config-syncer/intra-cluster/](https://appscode.com/products/kubed/v0.12.0/guides/config-syncer/intra-cluster/)

Install `kubed`
[helm chart](https://artifacthub.io/packages/helm/appscode/kubed)
and modify the
[default values](https://github.com/appscode/kubed/blob/master/charts/kubed/values.yaml).

```bash
helm repo add --force-update appscode https://charts.appscode.com/stable/ ; helm repo update > /dev/null
helm install --version v0.12.0 --namespace kubed --create-namespace --values - kubed appscode/kubed << EOF
imagePullPolicy: Always
config:
  clusterName: ${CLUSTER_FQDN}
EOF
```

Output:

```text
"appscode" has been added to your repositories
NAME: kubed
LAST DEPLOYED: Thu Dec 10 15:57:21 2020
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

Install `ingress-nginx`
[helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify the
[default values](https://github.com/kubernetes/ingress-nginx/blob/master/charts/ingress-nginx/values.yaml).

```bash
helm repo add --force-update ingress-nginx https://kubernetes.github.io/ingress-nginx ; helm repo update > /dev/null
helm install --version 3.15.2 --namespace ingress-nginx --create-namespace --wait --values - ingress-nginx ingress-nginx/ingress-nginx << EOF
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
LAST DEPLOYED: Thu Dec 10 16:00:57 2020
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

## Dex

```bash
helm repo add --force-update stable https://charts.helm.sh/stable ; helm repo update > /dev/null
helm install --version 2.15.1 --namespace dex --create-namespace --values - dex stable/dex << EOF
# https://github.com/helm/charts/blob/master/stable/dex/values.yaml
grpc: false
telemetry: true
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
  hosts:
    - dex.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - dex.${CLUSTER_FQDN}
config:
  issuer: https://dex.${CLUSTER_FQDN}
  connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: ${MY_GITHUB_ORG_OAUTH_CLIENT_ID}
        clientSecret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
        redirectURI: https://dex.${CLUSTER_FQDN}/callback
        orgs:
          - name: ${MY_GITHUB_ORG_NAME}
  staticClients:
    - id: argocd.${CLUSTER_FQDN}
      redirectURIs:
        - https://argocd.${CLUSTER_FQDN}/auth/callback
      name: ArgoCD
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
    - id: gangway.${CLUSTER_FQDN}
      redirectURIs:
        - https://gangway.${CLUSTER_FQDN}/callback
      name: Gangway
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
    - id: grafana.${CLUSTER_FQDN}
      redirectURIs:
        - https://grafana.${CLUSTER_FQDN}/login/generic_oauth
      name: Grafana
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
    - id: harbor.${CLUSTER_FQDN}
      redirectURIs:
        - https://harbor.${CLUSTER_FQDN}/c/oidc/callback
      name: Harbor
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
    - id: oauth2-proxy.${CLUSTER_FQDN}
      redirectURIs:
        - https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/callback
      name: OAuth2 Proxy
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
  enablePasswordDB: false
EOF
```

Output:

```text
"stable" has been added to your repositories
NAME: dex
LAST DEPLOYED: Thu Dec 10 16:01:52 2020
NAMESPACE: dex
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
1. Get the application URL by running these commands:
  https://dex.k1.k8s.mylabs.dev/
```

## oauth2-proxy

Install [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) to secure
the endpoints like (`prometheus.`, `alertmanager.`).

```bash
kubectl create namespace oauth2-proxy
helm install --version 3.2.5 --namespace oauth2-proxy --create-namespace --values - oauth2-proxy stable/oauth2-proxy << EOF
# https://github.com/helm/charts/blob/master/stable/oauth2-proxy/values.yaml
config:
  clientID: oauth2-proxy.${CLUSTER_FQDN}
  clientSecret: "${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}"
  cookieSecret: "$(openssl rand -base64 32 | head -c 32 | base64 )"
  configFile: |-
    email_domains = [ "*" ]
    upstreams = [ "file:///dev/null" ]
    whitelist_domains = ".${CLUSTER_FQDN}"
    cookie_domain = ".${CLUSTER_FQDN}"
    provider = "oidc"
    # Use http of non-valid certificates
    oidc_issuer_url = "https://dex.${CLUSTER_FQDN}"
    ssl_insecure_skip_verify = "true"
    insecure_oidc_skip_issuer_verification = "true"
image:
  pullPolicy: Always
ingress:
  enabled: true
  hosts:
    - oauth2-proxy.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - oauth2-proxy.${CLUSTER_FQDN}
resources:
  limits:
    cpu: 100m
    memory: 300Mi
  requests:
    cpu: 100m
    memory: 300Mi
EOF
```

Output:

```text
namespace/oauth2-proxy created
WARNING: This chart is deprecated
NAME: oauth2-proxy
LAST DEPLOYED: Thu Dec 10 16:02:08 2020
NAMESPACE: oauth2-proxy
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
To verify that oauth2-proxy has started, run:

  kubectl --namespace=oauth2-proxy get pods -l "app=oauth2-proxy"
```

## Gangway

::: danger
This is not working...
:::

Install gangway:

```shell
helm install --version 0.4.3 --namespace gangway --create-namespace --values - gangway stable/gangway << EOF
# https://github.com/helm/charts/blob/master/stable/gangway/values.yaml
gangway:
  clusterName: gangway.${CLUSTER_FQDN}
  authorizeURL: https://dex.${CLUSTER_FQDN}/auth
  # Needs to be http only because of non-valid certificate
  tokenURL: http://dex.${CLUSTER_FQDN}/token
  audience: https://dex.${CLUSTER_FQDN}/userinfo
  redirectURL: https://gangway.${CLUSTER_FQDN}/callback
  clientID: gangway.${CLUSTER_FQDN}
  clientSecret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
  apiServerURL: https://kube-oidc-proxy.${CLUSTER_FQDN}
ingress:
  enabled: true
  hosts:
    - gangway.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - gangway.${CLUSTER_FQDN}
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
  https://gangway.k1.k8s.mylabs.dev/
```

## kube-oidc-proxy

::: danger
This is not working...
:::

Install kube-oidc-proxy:

```shell
git clone --quiet https://github.com/jetstack/kube-oidc-proxy.git tmp/kube-oidc-proxy
git -C tmp/kube-oidc-proxy checkout --quiet v0.3.0

helm install --namespace kube-oidc-proxy --create-namespace --values - kube-oidc-proxy tmp/kube-oidc-proxy/deploy/charts/kube-oidc-proxy << EOF
# https://github.com/jetstack/kube-oidc-proxy/blob/master/deploy/charts/kube-oidc-proxy/values.yaml
oidc:
  clientId: kube-oidc-proxy.${CLUSTER_FQDN}
  issuerUrl: https://dex.${CLUSTER_FQDN}
  usernameClaim: email
  caPEM: |
$(curl -s https://letsencrypt.org/certs/fakelerootx1.pem | sed  "s/^/    /" )
ingress:
  enabled: false
  hosts:
    - host: kube-oidc-proxy.${CLUSTER_FQDN}
      paths:
        - /
  tls:
   - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
     hosts:
       - kube-oidc-proxy.${CLUSTER_FQDN}
EOF
```

## Istio

Download `istioctl`:

```bash
if [[ ! -f /usr/local/bin/istioctl ]]; then
  ISTIO_VERSION="1.8.1"
  if [[ $(uname) == "Darwin" ]]; then
    ISTIOCTL_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-osx.tar.gz"
  else
    ISTIOCTL_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-amd64.tar.gz"
  fi
  curl -s -L ${ISTIOCTL_URL} | sudo tar xz -C /usr/local/bin/
fi
```

Install Istio Operator:

```bash
# istioctl operator init --revision 1-8-2
```

## cluster-autoscaler

Install `autoscaler`
[helm chart](https://artifacthub.io/packages/helm/cluster-autoscaler/cluster-autoscaler)
and modify the
[default values](https://github.com/kubernetes/autoscaler/blob/master/charts/cluster-autoscaler/values.yaml).

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install --version 9.3.0 --namespace kube-system --values - cluster-autoscaler autoscaler/cluster-autoscaler << EOF
autoDiscovery:
  clusterName: ${CLUSTER_NAME}
awsRegion: ${AWS_DEFAULT_REGION}
serviceMonitor:
  enabled: true
  namespace: kube-prometheus-stack
EOF
```

Output:

```text
"autoscaler" has been added to your repositories
NAME: cluster-autoscaler
LAST DEPLOYED: Thu Dec 10 16:02:21 2020
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
To verify that cluster-autoscaler has started, run:

  kubectl --namespace=kube-system get pods -l "app.kubernetes.io/name=aws-cluster-autoscaler,app.kubernetes.io/instance=cluster-autoscaler"
```

## metrics-server

Enable Horizontal Pod Autoscaler by installing `metrics-server`:

```bash
helm install --version 2.11.2 --namespace kube-system metrics-server stable/metrics-server
```

Output:

```text
NAME: metrics-server
LAST DEPLOYED: Thu Dec 10 16:02:25 2020
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
NOTES:
The metric server has been deployed.

In a few minutes you should be able to list metrics using the following
command:

  kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes"
```
