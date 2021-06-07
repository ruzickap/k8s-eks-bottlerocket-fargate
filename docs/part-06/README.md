# Others

## Istio and related tools

### Jaeger

Install `jaeger-operator`
[helm chart](https://github.com/jaegertracing/helm-charts/tree/master/charts/jaeger-operator)
and modify the
[default values](https://github.com/jaegertracing/helm-charts/blob/master/charts/jaeger-operator/values.yaml).

```bash
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm upgrade --install --version 2.21.2 --namespace jaeger-operator --create-namespace --values - jaeger-operator jaegertracing/jaeger-operator << EOF
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
ISTIO_VERSION="1.10.0"

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
helm upgrade --install --version 1.35.0 --namespace kiali-operator --create-namespace kiali-operator kiali/kiali-operator
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
helm upgrade --install --version 9.9.2 --namespace kube-system --values - cluster-autoscaler autoscaler/cluster-autoscaler << EOF
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

You can test it by running `pause` container consuming `cpu: 3` resources :

```shell
kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pasue-deployment
  labels:
    app: pause
  annotations:
    ignore-check.kube-linter.io/no-read-only-root-fs : "Not needed"
spec:
  replicas: 4
  selector:
    matchLabels:
      app: pause
  template:
    metadata:
      labels:
        app: pause
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - topologyKey: "kubernetes.io/hostname"
            labelSelector:
              matchLabels:
                app: pause
      containers:
      - name: pause
        image: k8s.gcr.io/pause
        resources:
          requests:
            cpu: 100m
            memory: "64Mi"
          limits:
            cpu: 100m
            memory: "64Mi"
      securityContext:
        runAsUser: 10001
EOF
sleep 70
```

Check the details - some pods are still in pending state
(they are waiting for new node):

```shell
kubectl get pods -o wide
```

Output:

```text
NAME                                READY   STATUS    RESTARTS   AGE   IP              NODE                                              NOMINATED NODE   READINESS GATES
pasue-deployment-65dbbd9689-5jlr2   0/1     Pending   0          80s   <none>          <none>                                            <none>           <none>
pasue-deployment-65dbbd9689-b2c2c   0/1     Pending   0          80s   <none>          <none>                                            <none>           <none>
pasue-deployment-65dbbd9689-h2x42   1/1     Running   0          80s   172.16.67.45    ip-192-168-21-248.eu-central-1.compute.internal   <none>           <none>
pasue-deployment-65dbbd9689-jsxv7   1/1     Running   0          80s   172.16.81.187   ip-192-168-32-164.eu-central-1.compute.internal   <none>           <none>
pasue-deployment-65dbbd9689-rtrjj   1/1     Running   0          81s   172.16.237.53   ip-192-168-22-53.eu-central-1.compute.internal    <none>           <none>
```

The autoscaler ConfigMap should showing 1 more node which is starting up:

```shell
kubectl get configmap cluster-autoscaler-status -o yaml -n kube-system
```

Output:

```text
apiVersion: v1
data:
  status: |+
    Cluster-autoscaler status at 2021-05-08 17:20:34.053340145 +0000 UTC:
    Cluster-wide:
      Health:      Healthy (ready=3 unready=0 notStarted=1 longNotStarted=0 registered=4 longUnregistered=0)
                   LastProbeTime:      2021-05-08 17:20:33.899506348 +0000 UTC m=+80.696615970
                   LastTransitionTime: 2021-05-08 17:19:43.688753191 +0000 UTC m=+30.485862849
      ScaleUp:     InProgress (ready=3 registered=4)
                   LastProbeTime:      2021-05-08 17:20:33.899506348 +0000 UTC m=+80.696615970
                   LastTransitionTime: 2021-05-08 17:19:43.688753191 +0000 UTC m=+30.485862849
      ScaleDown:   CandidatesPresent (candidates=1)
                   LastProbeTime:      2021-05-08 17:20:33.899506348 +0000 UTC m=+80.696615970
                   LastTransitionTime: 2021-05-08 17:20:33.899506348 +0000 UTC m=+80.696615970

    NodeGroups:
      Name:        eks-7cbca64b-a46e-7860-4bfe-8318604c59f8
      Health:      Healthy (ready=3 unready=0 notStarted=1 longNotStarted=0 registered=4 longUnregistered=0 cloudProviderTarget=4 (minSize=2, maxSize=4))
                   LastProbeTime:      2021-05-08 17:20:33.899506348 +0000 UTC m=+80.696615970
                   LastTransitionTime: 2021-05-08 17:19:43.688753191 +0000 UTC m=+30.485862849
      ScaleUp:     InProgress (ready=3 cloudProviderTarget=4)
                   LastProbeTime:      2021-05-08 17:20:33.899506348 +0000 UTC m=+80.696615970
                   LastTransitionTime: 2021-05-08 17:19:43.688753191 +0000 UTC m=+30.485862849
      ScaleDown:   CandidatesPresent (candidates=1)
                   LastProbeTime:      2021-05-08 17:20:33.899506348 +0000 UTC m=+80.696615970
                   LastTransitionTime: 2021-05-08 17:20:33.899506348 +0000 UTC m=+80.696615970
...
```

The `cluster-autoscaler` should start one more node:

```shell
kubectl get nodes -L node.kubernetes.io/instance-type -L topology.kubernetes.io/zone
```

Output:

```text
NAME                                              STATUS     ROLES    AGE    VERSION              INSTANCE-TYPE   ZONE
ip-192-168-21-248.eu-central-1.compute.internal   Ready      <none>   111m   v1.19.6-eks-49a6c0   t3.xlarge       eu-central-1a
ip-192-168-22-53.eu-central-1.compute.internal    Ready      <none>   111m   v1.19.6-eks-49a6c0   t3.xlarge       eu-central-1a
ip-192-168-32-164.eu-central-1.compute.internal   Ready      <none>   111m   v1.19.6-eks-49a6c0   t3.xlarge       eu-central-1b
ip-192-168-59-184.eu-central-1.compute.internal   NotReady   <none>   11s    v1.19.6-eks-49a6c0   t3.xlarge       eu-central-1b
```

All pods should be running now and some of them are are on the new node:

```shell
sleep 30
kubectl get pods -o wide
```

Output:

```text
NAME                                              STATUS     ROLES    AGE    VERSION              INSTANCE-TYPE   ZONE
ip-192-168-21-248.eu-central-1.compute.internal   Ready      <none>   141m   v1.19.6-eks-49a6c0   t3.xlarge       eu-central-1a
ip-192-168-22-53.eu-central-1.compute.internal    Ready      <none>   141m   v1.19.6-eks-49a6c0   t3.xlarge       eu-central-1a
ip-192-168-32-164.eu-central-1.compute.internal   Ready      <none>   141m   v1.19.6-eks-49a6c0   t3.xlarge       eu-central-1b
ip-192-168-59-184.eu-central-1.compute.internal   Ready      <none>   41s    v1.19.6-eks-49a6c0   t3.xlarge       eu-central-1b
```

If you delete the deployment `autoscaler-demo` the `cluster-autoscaler` will
decrease the number of nodes:

```shell
kubectl delete deployment pasue-deployment
sleep 800
kubectl get nodes -L node.kubernetes.io/instance-type -L topology.kubernetes.io/zone
```
