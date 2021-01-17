# Others

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
