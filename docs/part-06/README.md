# Others

## Istio and related tools

### Jaeger

Install `jaeger-operator`
[helm chart](https://github.com/jaegertracing/helm-charts/tree/master/charts/jaeger-operator)
and modify the
[default values](https://github.com/jaegertracing/helm-charts/blob/master/charts/jaeger-operator/values.yaml).

```bash
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm install --version 2.19.0 --namespace jaeger-operator --create-namespace --values - jaeger-operator jaegertracing/jaeger-operator << EOF
rbac:
  clusterRole: true
EOF
```

Allow Jaeger to install Jaeger into `jaeger-controlplane`:

```bash
kubectl create namespace jaeger-system
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
ISTIO_VERSION="1.9.0"

if [[ ! -f /usr/local/bin/istioctl ]]; then
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
git clone --quiet https://github.com/istio/istio.git "tmp/${CLUSTER_FQDN}/istio"
git -C "tmp/${CLUSTER_FQDN}/istio" checkout --quiet "${ISTIO_VERSION}"

helm install istio-operator "tmp/${CLUSTER_FQDN}/istio/manifests/charts/istio-operator"
```

Create Istio using the operator:

```bash
kubectl create namespace istio-system
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
            service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "$(echo "${TAGS}" | tr " " ,)"
    pilot:
      k8s:
        overlays:
          - kind: Deployment
            name: istiod
            patches:
              - path: spec.template.spec.hostNetwork
                value: true
        # Reduce resource requirements for local testing. This is NOT
        # recommended for the real use cases.
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

Label the `default` namespace with `istio-injection=enabled`:

```shell
kubectl label namespace default istio-injection=enabled --overwrite
```

### Kiali

Install `kiali-operator`
[helm chart](https://github.com/kiali/helm-charts/tree/master/kiali-operator)
and modify the
[default values](https://github.com/kiali/helm-charts/blob/master/kiali-operator/values.yaml).

```bash
helm repo add kiali https://kiali.org/helm-charts
helm install --version 1.29.0 --namespace kiali-operator --create-namespace kiali-operator kiali/kiali-operator
```

Install Kiali CR:

```bash
# https://github.com/kiali/kiali-operator/blob/master/deploy/kiali/kiali_cr.yaml
kubectl create namespace kiali
kubectl create secret generic kiali --from-literal="oidc-secret=${MY_PASSWORD}" -n kiali
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
    image_version: operator_version
    namespace: kiali
    override_ingress_yaml:
      spec:
        rules:
        - host: kiali.${CLUSTER_FQDN}
          http:
            paths:
            - backend:
                serviceName: kiali
                servicePort: 20001
              path: /
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
rbac:
  serviceAccount:
    create: false
    name: cluster-autoscaler
serviceMonitor:
  enabled: true
  namespace: kube-prometheus-stack
EOF
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
