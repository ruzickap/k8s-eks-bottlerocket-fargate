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
helm repo add --force-update jetstack https://charts.jetstack.io
helm upgrade --install --version v1.5.3 --namespace cert-manager --wait --values - cert-manager jetstack/cert-manager << EOF
installCRDs: true
serviceAccount:
  create: false
  name: cert-manager
extraArgs:
  - --enable-certificate-owner-ref=true
prometheus:
  servicemonitor:
    enabled: true
webhook:
  # Needed for Calico
  securePort: 10251
  hostNetwork: true
EOF
sleep 10
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

kubectl wait --namespace cert-manager --timeout=10m --for=condition=Ready clusterissuer --all
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
  secretTemplate:
    annotations:
      kubed.appscode.com/sync: ""
  issuerRef:
    name: letsencrypt-${LETSENCRYPT_ENVIRONMENT}-dns
    kind: ClusterIssuer
  commonName: "*.${CLUSTER_FQDN}"
  dnsNames:
    - "*.${CLUSTER_FQDN}"
    - "${CLUSTER_FQDN}"
EOF

kubectl wait --namespace cert-manager --for=condition=Ready --timeout=20m certificate "ingress-cert-${LETSENCRYPT_ENVIRONMENT}"
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
helm repo add --force-update appscode https://charts.appscode.com/stable/
helm upgrade --install --version v0.12.0 --namespace kubed --create-namespace --values - kubed appscode/kubed << EOF
imagePullPolicy: Always
config:
  clusterName: ${CLUSTER_FQDN}
EOF
```

## ingress-nginx

Install `ingress-nginx`
[helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify the
[default values](https://github.com/kubernetes/ingress-nginx/blob/master/charts/ingress-nginx/values.yaml).

```bash
helm repo add --force-update ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install --version 3.35.0 --namespace ingress-nginx --create-namespace --wait --values - ingress-nginx ingress-nginx/ingress-nginx << EOF
controller:
  # Needed for Calico
  hostNetwork: true
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
    prometheusRule:
      enabled: true
      rules:
        - alert: NGINXConfigFailed
          expr: count(nginx_ingress_controller_config_last_reload_successful == 0) > 0
          for: 1s
          labels:
            severity: critical
          annotations:
            description: bad ingress config - nginx config test failed
            summary: uninstall the latest ingress changes to allow config reloads to resume
        - alert: NGINXCertificateExpiry
          expr: (avg(nginx_ingress_controller_ssl_expire_time_seconds) by (host) - time()) < 604800
          for: 1s
          labels:
            severity: critical
          annotations:
            description: ssl certificate(s) will expire in less then a week
            summary: renew expiring certificates to avoid downtime
        - alert: NGINXTooMany500s
          expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"5.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
          for: 1m
          labels:
            severity: warning
          annotations:
            description: Too many 5XXs
            summary: More than 5% of all requests returned 5XX, this requires your attention
        - alert: NGINXTooMany400s
          expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"4.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
          for: 1m
          labels:
            severity: warning
          annotations:
            description: Too many 4XXs
            summary: More than 5% of all requests returned 4XX, this requires your attention
EOF
```

## Istio and related tools

### Jaeger

Install `jaeger-operator`
[helm chart](https://github.com/jaegertracing/helm-charts/tree/master/charts/jaeger-operator)
and modify the
[default values](https://github.com/jaegertracing/helm-charts/blob/master/charts/jaeger-operator/values.yaml).

```bash
helm repo add --force-update jaegertracing https://jaegertracing.github.io/helm-charts
helm upgrade --install --version 2.23.0 --namespace jaeger-operator --create-namespace --values - jaeger-operator jaegertracing/jaeger-operator << EOF
rbac:
  clusterRole: true
EOF
```

Allow Jaeger to install Jaeger into `jaeger-controlplane`:

```bash
kubectl get namespace jaeger-system &> /dev/null || kubectl create namespace jaeger-system
# https://github.com/jaegertracing/jaeger-operator/blob/master/deploy/cluster_role_binding.yaml
kubectl apply -f - << EOF
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: jaeger-operator-in-jaeger-system
  namespace: jaeger-system
subjects:
  - kind: ServiceAccount
    name: jaeger-operator
    namespace: jaeger-operator
roleRef:
  kind: Role
  name: jaeger-operator
  apiGroup: rbac.authorization.k8s.io
EOF
```

Create Jaeger using the operator:

```bash
kubectl apply -f - << EOF
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  namespace: jaeger-system
  name: jaeger-controlplane
spec:
  strategy: AllInOne
  allInOne:
    image: jaegertracing/all-in-one:1.21
    options:
      log-level: debug
  storage:
    type: memory
    options:
      memory:
        max-traces: 100000
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - jaeger.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - jaeger.${CLUSTER_FQDN}
EOF
```

Allow Jaeger to be monitored by Prometheus [https://github.com/jaegertracing/jaeger-operator/issues/538](https://github.com/jaegertracing/jaeger-operator/issues/538):

```bash
kubectl apply -f - << EOF
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: tracing
  namespace: jaeger-system
spec:
  podMetricsEndpoints:
  - interval: 5s
    port: "admin-http"
  selector:
    matchLabels:
      app: jaeger
EOF
```

### Istio

Download `istioctl`:

```bash
ISTIO_VERSION="1.10.2"

if ! command -v istioctl &> /dev/null; then
  if [[ $(uname) == "Darwin" ]]; then
    ISTIOCTL_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-osx.tar.gz"
  else
    ISTIOCTL_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-amd64.tar.gz"
  fi
  curl -s -L ${ISTIOCTL_URL} | sudo tar xz -C /usr/local/bin/
fi
```

Clone the `istio` repository and install `istio-operator`
[helm chart](https://github.com/istio/istio/tree/master/manifests/charts/istio-operator)
and modify the
[default values](https://github.com/istio/istio/blob/master/manifests/charts/istio-operator/values.yaml).

```bash
test -d "tmp/${CLUSTER_FQDN}/istio" || git clone --quiet https://github.com/istio/istio.git "tmp/${CLUSTER_FQDN}/istio"
git -C "tmp/${CLUSTER_FQDN}/istio" checkout --quiet "${ISTIO_VERSION}"

helm upgrade --install istio-operator "tmp/${CLUSTER_FQDN}/istio/manifests/charts/istio-operator"
```

Create Istio using the operator:

```bash
kubectl get namespace istio-system &> /dev/null || kubectl create namespace istio-system
kubectl apply -f - << EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
  name: istio-controlplane
spec:
  profile: default
  meshConfig:
    enableTracing: true
    enableAutoMtls: true
    defaultConfig:
      tracing:
        zipkin:
          address: "jaeger-controlplane-collector-headless.jaeger-system.svc.cluster.local:9411"
        sampling: 100
      sds:
        enabled: true
  components:
    egressGateways:
      - name: istio-egressgateway
        enabled: true
    ingressGateways:
      - name: istio-ingressgateway
        enabled: true
        k8s:
          serviceAnnotations:
            service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
            service.beta.kubernetes.io/aws-load-balancer-type: nlb
            service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "${TAGS// /,}"
    pilot:
      k8s:
        overlays:
          - kind: Deployment
            name: istiod
            patches:
              - path: spec.template.spec.hostNetwork
                value: true
        # Reduce resource requirements for local testing. This is NOT recommended for the real use cases
        resources:
          limits:
            cpu: 200m
            memory: 128Mi
          requests:
            cpu: 100m
            memory: 64Mi
EOF
```

Enable Prometheus monitoring:

```bash
kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/extras/prometheus-operator.yaml"
```

### Kiali

Install `kiali-operator`
[helm chart](https://github.com/kiali/helm-charts/tree/master/kiali-operator)
and modify the
[default values](https://github.com/kiali/helm-charts/blob/master/kiali-operator/values.yaml).

```bash
helm repo add --force-update kiali https://kiali.org/helm-charts
helm upgrade --install --version 1.38.1 --namespace kiali-operator --create-namespace kiali-operator kiali/kiali-operator
```

Install Kiali CR:

```bash
# https://github.com/kiali/kiali-operator/blob/master/deploy/kiali/kiali_cr.yaml
kubectl get namespace kiali &> /dev/null || kubectl create namespace kiali
kubectl get secret -n kiali kiali || kubectl create secret generic kiali --from-literal="oidc-secret=${MY_PASSWORD}" -n kiali
kubectl apply -f - << EOF
apiVersion: kiali.io/v1alpha1
kind: Kiali
metadata:
  namespace: kiali-operator
  name: kiali
spec:
  istio_namespace: istio-system
  auth:
    strategy: openid
    openid:
      client_id: kiali.${CLUSTER_FQDN}
      disable_rbac: true
      insecure_skip_verify_tls: true
      issuer_uri: "https://dex.${CLUSTER_FQDN}"
      username_claim: email
  deployment:
    accessible_namespaces: ["**"]
    namespace: kiali
    override_ingress_yaml:
      spec:
        rules:
        - host: kiali.${CLUSTER_FQDN}
          http:
            paths:
            - path: /
              pathType: ImplementationSpecific
              backend:
                service:
                  name: kiali
                  port:
                    number: 20001
          tls:
            - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
              hosts:
                - kiali.${CLUSTER_FQDN}
  external_services:
    grafana:
      is_core_component: true
      url: "https://grafana.${CLUSTER_FQDN}"
      in_cluster_url: "http://kube-prometheus-stack-grafana.kube-prometheus-stack.svc.cluster.local:80"
    prometheus:
      is_core_component: true
      url: http://kube-prometheus-stack-prometheus.kube-prometheus-stack.svc.cluster.local:9090
    tracing:
      is_core_component: true
      url: https://jaeger.${CLUSTER_FQDN}
      in_cluster_url: http://jaeger-controlplane-query.jaeger-system.svc.cluster.local:16686
  server:
    web_fqdn: kiali.${CLUSTER_FQDN}
    web_root: /
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
helm repo add --force-update bitnami https://charts.bitnami.com/bitnami
helm upgrade --install --version 5.4.1 --namespace external-dns --values - external-dns bitnami/external-dns << EOF
sources:
  - ingress
  - istio-gateway
  - istio-virtualservice
  - service
aws:
  region: ${AWS_DEFAULT_REGION}
domainFilters:
  - ${CLUSTER_FQDN}
interval: 20s
policy: sync
serviceAccount:
  create: false
  name: external-dns
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
helm repo add --force-update codecentric https://codecentric.github.io/helm-charts
helm upgrade --install --version 4.1.0 --namespace mailhog --create-namespace --values - mailhog codecentric/mailhog << EOF
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

```bash
helm upgrade --install --version 3.2.13 --namespace kubewatch --create-namespace --values - kubewatch bitnami/kubewatch << EOF
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
  requireTLS: false
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

```bash
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
calicoctl --allow-version-mismatch ipam show --show-block
```

Output:

```text
+----------+-------------------+-----------+------------+--------------+
| GROUPING |       CIDR        | IPS TOTAL | IPS IN USE |   IPS FREE   |
+----------+-------------------+-----------+------------+--------------+
| IP Pool  | 172.16.0.0/16     |     65536 | 42 (0%)    | 65494 (100%) |
| Block    | 172.16.166.128/26 |        64 | 14 (22%)   | 50 (78%)     |
| Block    | 172.16.2.128/26   |        64 | 13 (20%)   | 51 (80%)     |
| Block    | 172.16.3.64/26    |        64 | 15 (23%)   | 49 (77%)     |
+----------+-------------------+-----------+------------+--------------+
```

Block outgoing traffic form `calico-test-1` namespace:

```bash
kubectl get namespace calico-test-1 &> /dev/null || kubectl create namespace calico-test-1

calicoctl --allow-version-mismatch apply -f - << EOF
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

kubectl run curl-test-1 --timeout=10m --namespace calico-test-1 --image=radial/busyboxplus:curl --rm -it -- ping -c 3 -w 50 www.google.com
```

Output:

```text
--- www.google.com ping statistics ---
50 packets transmitted, 0 packets received, 100% packet loss
```

Try the same in `calico-test-2`, but allow traffic to `1.1.1.1`:

```bash
kubectl get namespace calico-test-2 &> /dev/null || kubectl create namespace calico-test-2

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
round-trip min/avg/max = 1.309/1.348/1.399 ms
```

Ping should be working fine in namespaces which doesn't start with `calico-test`
(like `default`):

```bash
kubectl run curl-test --namespace default --image=radial/busyboxplus:curl --rm -it -- ping -c 3 -w 50 www.google.com
```

Output:

```text
--- www.google.com ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 1.398/1.417/1.430 ms
```
