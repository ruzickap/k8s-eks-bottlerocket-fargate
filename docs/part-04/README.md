# DNS, Ingress, Certificates

Install the basic tools, before running some applications like DNS integration
([external-dns](https://github.com/kubernetes-sigs/external-dns)), Ingress ([ingress-nginx](https://kubernetes.github.io/ingress-nginx/)),
certificate management ([cert-manager](https://cert-manager.io/)), ...

## cert-manager

Install `cert-manager`
[helm chart](https://artifacthub.io/packages/helm/jetstack/cert-manager)
and modify the
[default values](https://github.com/jetstack/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml).
Service account `external-dns` was created by `eksctl`.

```bash
helm repo add jetstack https://charts.jetstack.io
helm install --version v1.3.1 --namespace cert-manager --wait --wait-for-jobs --values - cert-manager jetstack/cert-manager << EOF
installCRDs: true
serviceAccount:
  create: false
  name: cert-manager
extraArgs:
  - --enable-certificate-owner-ref=true
securityContext:
  enabled: true
prometheus:
  servicemonitor:
    enabled: true
webhook:
  # Needed for calico
  securePort: 10251
  hostNetwork: true
EOF
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

Annotate the wildcard certificate secret. It will allow `kubed` to distribute
it to all namespaces.

```bash
kubectl wait --namespace cert-manager --for=condition=Ready --timeout=15m certificate "ingress-cert-${LETSENCRYPT_ENVIRONMENT}"
kubectl annotate secret "ingress-cert-${LETSENCRYPT_ENVIRONMENT}" -n cert-manager kubed.appscode.com/sync=""
```

## ingress-nginx

Install `ingress-nginx`
[helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify the
[default values](https://github.com/kubernetes/ingress-nginx/blob/master/charts/ingress-nginx/values.yaml).

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install --version 3.29.0 --namespace ingress-nginx --create-namespace --wait --wait-for-jobs --values - ingress-nginx ingress-nginx/ingress-nginx << EOF
controller:
  # Needed for calico
  hostNetwork: true
  extraArgs:
    default-ssl-certificate: cert-manager/ingress-cert-${LETSENCRYPT_ENVIRONMENT}
  replicaCount: 1
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "$(echo "${TAGS}" | tr " " ,)"
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
EOF
```

## external-dns

Install `external-dns`
[helm chart](https://artifacthub.io/packages/helm/bitnami/external-dns)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/external-dns/values.yaml).
`external-dns` will take care about DNS records.
Service account `external-dns` was created by `eksctl`.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install --version 4.11.0 --namespace external-dns --values - external-dns bitnami/external-dns << EOF
sources:
  - ingress
  - istio-gateway
  - istio-virtualservice
  - service
aws:
  region: ${AWS_DEFAULT_REGION}
domainFilters:
  - ${CLUSTER_FQDN}
interval: 10s
policy: sync
replicas: 1
serviceAccount:
  create: false
  name: external-dns
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

## mailhog

Install `mailhog`
[helm chart](https://artifacthub.io/packages/helm/codecentric/mailhog)
and modify the
[default values](https://github.com/codecentric/helm-charts/blob/master/charts/mailhog/values.yaml).

```bash
helm repo add codecentric https://codecentric.github.io/helm-charts
helm install --version 4.1.0 --namespace mailhog --create-namespace --values - mailhog codecentric/mailhog << EOF
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - host: mailhog.${CLUSTER_FQDN}
      paths: ["/"]
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - mailhog.${CLUSTER_FQDN}
EOF
```

## kubewatch

Install `kubewatch`
[helm chart](https://artifacthub.io/packages/helm/bitnami/kubewatch)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/kubewatch/values.yaml).

Details: [Kubernetes Event Notifications to a Slack Channel](https://www.powerupcloud.com/kubernetes-event-notifications-to-a-slack-channel-part-v/)

```shell
helm install --version 3.2.3 --namespace kubewatch --create-namespace --values - kubewatch bitnami/kubewatch << EOF
slack:
  enabled: true
  channel: "#${SLACK_CHANNEL}"
  token: ${SLACK_BOT_API_TOKEN}
smtp:
  enabled: true
  to: "notification@${CLUSTER_FQDN}"
  from: "kubewatch@${CLUSTER_FQDN}"
  smarthost: "mailhog.mailhog.svc.cluster.local:1025"
  subject: "kubewatch"
resourcesToWatch:
  deployment: false
  pod: false
  persistentvolume: true
  namespace: true
rbac:
  create: false
EOF
```

Create `ClusterRole` and `ClusterRoleBinding` to allow `kubewatch` to access
necessary resources:

```shell
kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: system:kubewatch
rules:
- apiGroups:
  - ""
  resources:
  - namespaces
  - persistentvolumes
  verbs:
  - list
  - watch
  - get
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kubewatch
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kubewatch
subjects:
- kind: ServiceAccount
  name: kubewatch
  namespace: kubewatch
EOF
```

## Calico commands

```bash
calicoctl ipam show --show-block
```

Output:

```text
+----------+------------------+-----------+------------+--------------+
| GROUPING |       CIDR       | IPS TOTAL | IPS IN USE |   IPS FREE   |
+----------+------------------+-----------+------------+--------------+
| IP Pool  | 172.16.0.0/16    |     65536 | 15 (0%)    | 65521 (100%) |
| Block    | 172.16.31.64/26  |        64 | 4 (6%)     | 60 (94%)     |
| Block    | 172.16.71.192/26 |        64 | 6 (9%)     | 58 (91%)     |
| Block    | 172.16.82.192/26 |        64 | 5 (8%)     | 59 (92%)     |
+----------+------------------+-----------+------------+--------------+
```

Block outgoing traffic form `calico-test-1` namespace:

```shell
kubectl create namespace calico-test-1

calicoctl apply -f - << EOF
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: calico-test-disable-all-egress
spec:
  namespaceSelector: has(projectcalico.org/name) && projectcalico.org/name starts with "calico-test"
  types:
  - Ingress
  - Egress
  ingress:
  - action: Allow
  egress:
  # Except DNS
  - action: Allow
    protocol: TCP
    destination:
      ports:
      - 53
  - action: Allow
    protocol: UDP
    destination:
      ports:
      - 53
EOF

kubectl run curl-test-1 --namespace calico-test-1 --image=radial/busyboxplus:curl --rm -it -- ping -c 3 -w 50 www.google.com
```

Output:

```text
--- www.google.com ping statistics ---
50 packets transmitted, 0 packets received, 100% packet loss
```

Try the same in `calico-test-2`, but allow traffic to `1.1.1.1`:

```shell
kubectl create namespace calico-test-2

kubectl apply -f - << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-1.1.1.1
  namespace: calico-test-2
spec:
  podSelector: {}
  egress:
  - to:
    - ipBlock:
        cidr: 1.1.1.1/32
EOF

kubectl run curl-test-1 --namespace calico-test-2 --image=radial/busyboxplus:curl --rm -it -- ping -c 3 -w 50 www.google.com
kubectl run curl-test-2 --namespace calico-test-2 --image=radial/busyboxplus:curl --rm -it -- ping -c 3 -w 50 1.1.1.1
```

Output:

```text
--- www.google.com ping statistics ---
50 packets transmitted, 0 packets received, 100% packet loss

--- 1.1.1.1 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 1.333/1.863/2.795 ms
```

Ping should be working fine in namespaces which doesn't start with `calico-test`
(like `default`):

```shell
kubectl run curl-test --namespace default --image=radial/busyboxplus:curl --rm -it -- ping -c 3 -w 50 www.google.com
```

Output:

```text
--- www.google.com ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 1.523/1.653/1.729 ms
```
