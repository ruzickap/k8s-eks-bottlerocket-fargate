# Others

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
# Required to fix IMDSv2 issue: https://github.com/kubernetes/autoscaler/issues/3592
extraArgs:
  aws-use-static-instance-list: true
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
