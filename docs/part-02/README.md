# K8s tools

Install the basic tools, before running some applications like monitoring
([Prometheus](https://prometheus.io)), DNS integration
([external-dns](https://github.com/kubernetes-sigs/external-dns)), Ingress ([ingress-nginx](https://kubernetes.github.io/ingress-nginx/)),
certificate management ([cert-manager](https://cert-manager.io/)), ...

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

## aws-efs-csi-driver

Install [Amazon EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver),
which supports ReadWriteMany PVC, is installed.

Install [Amazon EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver)
`aws-efs-csi-driver`
[helm chart](https://github.com/kubernetes-sigs/aws-efs-csi-driver/tree/master/helm)
and modify the
[default values](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/helm/values.yaml):

```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
kubectl delete CSIDriver efs.csi.aws.com
helm install --version 0.1.0 --namespace kube-system --values - aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver << EOF
# Use newer version of the container image due to the bug:
# https://github.com/kubernetes-sigs/aws-efs-csi-driver/issues/192
image:
  tag: "9c4d851"
EOF
```

Create storage class for EFS:

```bash
kubectl apply -f - << EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs
provisioner: efs.csi.aws.com
EOF
```

## aws-ebs-csi-driver

```bash
EKSCTL_IAM_SERVICE_ACCOUNTS=$(eksctl get iamserviceaccount --cluster=${CLUSTER_NAME} --namespace kube-system -o json)
EBS_CONTROLLER_ROLE_ARN=$(echo "${EKSCTL_IAM_SERVICE_ACCOUNTS}" | jq -r ".iam.serviceAccounts[] | select(.metadata.name==\"ebs-csi-controller-sa\") .status.roleARN")
EBS_SNAPSHOT_ROLE_ARN=$(echo "${EKSCTL_IAM_SERVICE_ACCOUNTS}" | jq -r ".iam.serviceAccounts[] | select(.metadata.name==\"ebs-snapshot-controller\") .status.roleARN")
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
enableVolumeSnapshot: true
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

Create new `gp3` storage class using `aws-ebs-csi-driver`:

```bash
kubectl apply -f - << EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF
```

Set `gp3` as default StorageClass:

```bash
kubectl patch storageclass gp3 -p "{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}"
kubectl patch storageclass gp2 -p "{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}"
```

## external-snapshotter CRDs

Details about EKS and external-snapshotter can be found here: [https://aws.amazon.com/blogs/containers/using-ebs-snapshots-for-persistent-storage-with-your-eks-cluster](https://aws.amazon.com/blogs/containers/using-ebs-snapshots-for-persistent-storage-with-your-eks-cluster)

Install  Volume Snapshot Custom Resource Definitions (CRDs)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
```

Create the Volume Snapshot Class:

```bash
kubectl apply -f - << EOF
apiVersion: snapshot.storage.k8s.io/v1beta1
kind: VolumeSnapshotClass
metadata:
  name: csi-ebs-snapclass
  labels:
    velero.io/csi-volumesnapshot-class: "true"
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: ebs.csi.aws.com
deletionPolicy: Retain
EOF
```

## metrics-server

Install `metrics-server`
[helm chart](https://artifacthub.io/packages/helm/bitnami/metrics-server)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/metrics-server/values.yaml):

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install --version 5.3.2 --namespace metrics-server --create-namespace --values - metrics-server bitnami/metrics-server << EOF
apiService:
  create: true
EOF
```

## kube-prometheus-stack

Install `kube-prometheus-stack`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
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

helm repo add jetstack https://charts.jetstack.io
helm install --version v1.1.0 --namespace cert-manager --create-namespace --wait --values - cert-manager jetstack/cert-manager << EOF
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
helm repo add bitnami https://charts.bitnami.com/bitnami
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
helm repo add appscode https://charts.appscode.com/stable/
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
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install --version 3.16.1 --namespace ingress-nginx --create-namespace --wait --values - ingress-nginx ingress-nginx/ingress-nginx << EOF
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
helm repo add stable https://charts.helm.sh/stable
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
    - id: vault.${CLUSTER_FQDN}
      redirectURIs:
        - https://vault.${CLUSTER_FQDN}/ui/vault/auth/oidc/oidc/callback
        - http://localhost:8250/oidc/callback
      name: Vault
      secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
  enablePasswordDB: false
EOF
sleep 50
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

Install gangway:

```bash
helm install --version 0.4.3 --namespace gangway --create-namespace --values - gangway stable/gangway << EOF
# https://github.com/helm/charts/blob/master/stable/gangway/values.yaml
trustedCACert: |
$(curl -s https://letsencrypt.org/certs/fakelerootx1.pem | sed  "s/^/  /" )
gangway:
  clusterName: ${CLUSTER_FQDN}
  authorizeURL: https://dex.${CLUSTER_FQDN}/auth
  tokenURL: https://dex.${CLUSTER_FQDN}/token
  audience: https://dex.${CLUSTER_FQDN}/userinfo
  redirectURL: https://gangway.${CLUSTER_FQDN}/callback
  clientID: gangway.${CLUSTER_FQDN}
  clientSecret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
  apiServerURL: https://kube-oidc-proxy.${CLUSTER_FQDN}
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
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

The `kube-oidc-proxy` accepting connections only via HTTPS. It's necessary to
configure ingress to communicate with the backend over HTTPS.

Install kube-oidc-proxy:

```bash
git clone --quiet https://github.com/jetstack/kube-oidc-proxy.git tmp/kube-oidc-proxy
git -C tmp/kube-oidc-proxy checkout --quiet v0.3.0

helm install --namespace kube-oidc-proxy --create-namespace --values - kube-oidc-proxy tmp/kube-oidc-proxy/deploy/charts/kube-oidc-proxy << EOF
# https://github.com/jetstack/kube-oidc-proxy/blob/master/deploy/charts/kube-oidc-proxy/values.yaml
oidc:
  clientId: gangway.${CLUSTER_FQDN}
  issuerUrl: https://dex.${CLUSTER_FQDN}
  usernameClaim: email
  caPEM: |
$(curl -s https://letsencrypt.org/certs/fakelerootx1.pem | sed  "s/^/    /" )
ingress:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
  enabled: true
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

If you get the credentials form the [https://gangway.k1.k8s.mylabs.dev](https://gangway.k1.k8s.mylabs.dev)
you will have the access to the cluster, but no rights there.

Add access rights to the user:

```bash
kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: kube-prometheus-stack
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-secrets
  namespace: kube-prometheus-stack
subjects:
- kind: User
  name: ${MY_EMAIL}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pods-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: read-pods
subjects:
- kind: User
  name: ${MY_EMAIL}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: pods-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

The user should be able to read the secrets in `kube-prometheus-stack`
namespace:

```shell
kubectl describe secrets --insecure-skip-tls-verify -n kube-prometheus-stack "ingress-cert-${LETSENCRYPT_ENVIRONMENT}"
```

Output:

```text
Name:         ingress-cert-staging
Namespace:    kube-prometheus-stack
Labels:       kubed.appscode.com/origin.cluster=k1.k8s.mylabs.dev
              kubed.appscode.com/origin.name=ingress-cert-staging
              kubed.appscode.com/origin.namespace=cert-manager
Annotations:  cert-manager.io/alt-names: *.k1.k8s.mylabs.dev,k1.k8s.mylabs.dev
              cert-manager.io/certificate-name: ingress-cert-staging
              cert-manager.io/common-name: *.k1.k8s.mylabs.dev
              cert-manager.io/ip-sans:
              cert-manager.io/issuer-group:
              cert-manager.io/issuer-kind: ClusterIssuer
              cert-manager.io/issuer-name: letsencrypt-staging-dns
              cert-manager.io/uri-sans:
              kubed.appscode.com/origin:
                {"namespace":"cert-manager","name":"ingress-cert-staging","uid":"f1ed062c-23d9-4cf7-ad51-cfafd8a3b788","resourceVersion":"5296"}

Type:  kubernetes.io/tls

Data
====
tls.crt:  3586 bytes
tls.key:  1679 bytes
```

But it's not allowed to delete the secrets for the user:

```shell
kubectl delete secrets --insecure-skip-tls-verify -n kube-prometheus-stack "ingress-cert-${LETSENCRYPT_ENVIRONMENT}"
```

Output:

```text
Error from server (Forbidden): secrets "ingress-cert-staging" is forbidden: User "petr.ruzicka@gmail.com" cannot delete resource "secrets" in API group "" in the namespace "kube-prometheus-stack"
```

The user can not read secrets outside the `kube-prometheus-stack`:

```shell
kubectl get secrets --insecure-skip-tls-verify -n kube-system
```

Output:

```text
Error from server (Forbidden): secrets is forbidden: User "petr.ruzicka@gmail.com" cannot list resource "secrets" in API group "" in the namespace "kube-system"
```

You can see the pods "everywhere":

```shell
kubectl get pods --insecure-skip-tls-verify -n kube-system
```

Output:

```text
NAME                                                         READY   STATUS    RESTARTS   AGE
aws-for-fluent-bit-5hxlt                                     1/1     Running   0          32m
aws-for-fluent-bit-dmvzq                                     1/1     Running   0          32m
aws-node-ggfft                                               1/1     Running   0          32m
aws-node-lhlvf                                               1/1     Running   0          32m
cluster-autoscaler-aws-cluster-autoscaler-7f878bccc8-s279k   1/1     Running   0          25m
coredns-59b69b4849-6v487                                     1/1     Running   0          46m
coredns-59b69b4849-tw2dg                                     1/1     Running   0          46m
ebs-csi-controller-86785d75db-7brbr                          5/5     Running   0          31m
ebs-csi-controller-86785d75db-gn4ll                          5/5     Running   0          31m
ebs-csi-node-6h9zv                                           3/3     Running   0          31m
ebs-csi-node-r5rj7                                           3/3     Running   0          31m
kube-proxy-m6dm8                                             1/1     Running   0          32m
kube-proxy-pdmv9                                             1/1     Running   0          32m
```

But you can not delete them:

```shell
kubectl delete pods --insecure-skip-tls-verify -n kube-oidc-proxy --all
```

Output:

```text
Error from server (Forbidden): pods "kube-oidc-proxy-74bf5679fd-jhdmr" is forbidden: User "petr.ruzicka@gmail.com" cannot delete resource "pods" in API group "" in the namespace "kube-oidc-proxy"
```

## Istio

Download `istioctl`:

```shell
ISTIO_VERSION="1.8.2"

if [[ ! -f /usr/local/bin/istioctl ]]; then
  if [[ $(uname) == "Darwin" ]]; then
    ISTIOCTL_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-osx.tar.gz"
  else
    ISTIOCTL_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-amd64.tar.gz"
  fi
  curl -s -L ${ISTIOCTL_URL} | sudo tar xz -C /usr/local/bin/
fi
```

Install Istio Operator:

```shell
istioctl operator init --revision ${ISTIO_VERSION//./-}
```

## cluster-autoscaler

Install `cluster-autoscaler`
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

You can test it by running:

```shell
kubectl create deployment autoscaler-demo --image=nginx
kubectl scale deployment autoscaler-demo --replicas=50
```

The `cluster-autoscaler` should start one more node and run there the pods:

```shell
kubectl get nodes
```

Output:

```text
NAME                                              STATUS   ROLES    AGE     VERSION
ip-192-168-25-231.eu-central-1.compute.internal   Ready    <none>   18m     v1.18.9-eks-d1db3c
ip-192-168-55-65.eu-central-1.compute.internal    Ready    <none>   2m17s   v1.18.9-eks-d1db3c
ip-192-168-59-105.eu-central-1.compute.internal   Ready    <none>   18m     v1.18.9-eks-d1db3c
```

If you delete the deployment `autoscaler-demo` the `cluster-autoscaler` will
decrease the number of nodes:

```shell
kubectl delete deployment autoscaler-demo
kubectl get nodes
```
