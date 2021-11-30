# Others

## cluster-autoscaler

Install `cluster-autoscaler`
[helm chart](https://artifacthub.io/packages/helm/cluster-autoscaler/cluster-autoscaler)
and modify the
[default values](https://github.com/kubernetes/autoscaler/blob/master/charts/cluster-autoscaler/values.yaml).

```bash
helm repo add --force-update autoscaler https://kubernetes.github.io/autoscaler
helm upgrade --install --version 9.10.4 --namespace kube-system --wait --values - cluster-autoscaler autoscaler/cluster-autoscaler << EOF
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
prometheusRule:
  enabled: false
  namespace: kube-prometheus-stack
EOF
sleep 10
```

You can test it by running `pause` container consuming `cpu: 3` resources :

```bash
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
  replicas: 15
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
            memory: "1024Mi"
          limits:
            cpu: 100m
            memory: "1024Mi"
      securityContext:
        runAsUser: 10001
EOF
```

There should be 3 nodes started by default:

```bash
kubectl get nodes -L node.kubernetes.io/instance-type -L topology.kubernetes.io/zone
sleep 70
```

Output:

```text
NAME                                           STATUS   ROLES    AGE   VERSION   INSTANCE-TYPE   ZONE
ip-192-168-31-11.eu-west-1.compute.internal    Ready    <none>   21m   v1.21.6   t3.xlarge       eu-west-1a
ip-192-168-56-82.eu-west-1.compute.internal    Ready    <none>   21m   v1.21.6   t3.xlarge       eu-west-1b
ip-192-168-60-184.eu-west-1.compute.internal   Ready    <none>   21m   v1.21.6   t3.xlarge       eu-west-1b
```

Check the details - some pods are still in pending state
(they are waiting for new node):

```bash
kubectl get pods -o wide
```

Output:

```text
NAME                                READY   STATUS              RESTARTS   AGE   IP               NODE                                           NOMINATED NODE   READINESS GATES
pasue-deployment-648c54d8c6-498tx   0/1     Pending             0          70s   <none>           <none>                                         <none>           <none>
pasue-deployment-648c54d8c6-4wr5f   1/1     Running             0          71s   172.16.166.146   ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-579dx   1/1     Running             0          70s   172.16.2.147     ip-192-168-31-11.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-5vqrr   1/1     Running             0          70s   172.16.3.89      ip-192-168-60-184.eu-west-1.compute.internal   <none>           <none>
pasue-deployment-648c54d8c6-5zr8k   1/1     Running             0          70s   172.16.166.147   ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-7kd65   0/1     ContainerCreating   0          70s   <none>           ip-192-168-3-25.eu-west-1.compute.internal     <none>           <none>
pasue-deployment-648c54d8c6-kknlr   1/1     Running             0          70s   172.16.3.88      ip-192-168-60-184.eu-west-1.compute.internal   <none>           <none>
pasue-deployment-648c54d8c6-pcsb8   0/1     ContainerCreating   0          70s   <none>           ip-192-168-3-25.eu-west-1.compute.internal     <none>           <none>
pasue-deployment-648c54d8c6-qcdpw   1/1     Running             0          70s   172.16.2.146     ip-192-168-31-11.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-s8qcm   0/1     ContainerCreating   0          70s   <none>           ip-192-168-3-25.eu-west-1.compute.internal     <none>           <none>
pasue-deployment-648c54d8c6-sl7mb   0/1     Pending             0          70s   <none>           <none>                                         <none>           <none>
pasue-deployment-648c54d8c6-v7b5x   1/1     Running             0          71s   172.16.3.87      ip-192-168-60-184.eu-west-1.compute.internal   <none>           <none>
pasue-deployment-648c54d8c6-vmshk   1/1     Running             0          71s   172.16.2.145     ip-192-168-31-11.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-zfqfx   1/1     Running             0          70s   172.16.166.148   ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-zpmg5   0/1     ContainerCreating   0          70s   <none>           ip-192-168-3-25.eu-west-1.compute.internal     <none>           <none>
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
    Cluster-autoscaler status at 2021-11-29 17:44:03.335055488 +0000 UTC:
    Cluster-wide:
      Health:      Healthy (ready=4 unready=0 notStarted=1 longNotStarted=0 registered=5 longUnregistered=0)
                   LastProbeTime:      2021-11-29 17:44:03.332119893 +0000 UTC m=+82.224475909
                   LastTransitionTime: 2021-11-29 17:42:52.673668227 +0000 UTC m=+11.566024230
      ScaleUp:     InProgress (ready=4 registered=5)
                   LastProbeTime:      2021-11-29 17:44:03.332119893 +0000 UTC m=+82.224475909
                   LastTransitionTime: 2021-11-29 17:43:02.702663909 +0000 UTC m=+21.595019844
      ScaleDown:   NoCandidates (candidates=0)
                   LastProbeTime:      2021-11-29 17:44:03.332119893 +0000 UTC m=+82.224475909
                   LastTransitionTime: 2021-11-29 17:44:03.332119893 +0000 UTC m=+82.224475909

    NodeGroups:
      Name:        eks-managed-ng-1-04beb65b-308f-11f3-e139-b0ebbe48a090
      Health:      Healthy (ready=4 unready=0 notStarted=1 longNotStarted=0 registered=5 longUnregistered=0 cloudProviderTarget=5 (minSize=2, maxSize=5))
                   LastProbeTime:      2021-11-29 17:44:03.332119893 +0000 UTC m=+82.224475909
                   LastTransitionTime: 2021-11-29 17:42:52.673668227 +0000 UTC m=+11.566024230
      ScaleUp:     InProgress (ready=4 cloudProviderTarget=5)
                   LastProbeTime:      2021-11-29 17:44:03.332119893 +0000 UTC m=+82.224475909
                   LastTransitionTime: 2021-11-29 17:43:02.702663909 +0000 UTC m=+21.595019844
      ScaleDown:   NoCandidates (candidates=0)
                   LastProbeTime:      2021-11-29 17:44:03.332119893 +0000 UTC m=+82.224475909
                   LastTransitionTime: 2021-11-29 17:44:03.332119893 +0000 UTC m=+82.224475909

kind: ConfigMap
metadata:
  annotations:
    cluster-autoscaler.kubernetes.io/last-updated: 2021-11-29 17:44:03.335055488 +0000
      UTC
  creationTimestamp: "2021-11-29T17:42:41Z"
  name: cluster-autoscaler-status
  namespace: kube-system
  resourceVersion: "16437"
  uid: 5b5084d7-9af3-4665-b829-ab210c9a633d
```

```bash
# shellcheck disable=SC1083
kubectl logs -n kube-system --since=1m "$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler -o=jsonpath="{.items[0].metadata.name}")"
sleep 100
```

Output:

```text
...
I1129 17:43:53.270450       1 static_autoscaler.go:228] Starting main loop
I1129 17:43:53.292923       1 filter_out_schedulable.go:65] Filtering out schedulables
I1129 17:43:53.292975       1 filter_out_schedulable.go:132] Filtered out 0 pods using hints
I1129 17:43:53.293049       1 filter_out_schedulable.go:157] Pod default.pasue-deployment-648c54d8c6-pcsb8 marked as unschedulable can be scheduled on node template-node-for-eks-managed-ng-1-04beb65b-308f-11f3-e139-b0ebbe48a090-4548432111829895923-0. Ignoring in scale up.
I1129 17:43:53.293094       1 filter_out_schedulable.go:157] Pod default.pasue-deployment-648c54d8c6-7kd65 marked as unschedulable can be scheduled on node template-node-for-eks-managed-ng-1-04beb65b-308f-11f3-e139-b0ebbe48a090-4548432111829895923-0. Ignoring in scale up.
I1129 17:43:53.293120       1 filter_out_schedulable.go:157] Pod default.pasue-deployment-648c54d8c6-498tx marked as unschedulable can be scheduled on node template-node-for-eks-managed-ng-1-04beb65b-308f-11f3-e139-b0ebbe48a090-4548432111829895923-0. Ignoring in scale up.
I1129 17:43:53.293147       1 filter_out_schedulable.go:157] Pod default.pasue-deployment-648c54d8c6-sl7mb marked as unschedulable can be scheduled on node template-node-for-eks-managed-ng-1-04beb65b-308f-11f3-e139-b0ebbe48a090-4548432111829895923-0. Ignoring in scale up.
I1129 17:43:53.293176       1 filter_out_schedulable.go:157] Pod default.pasue-deployment-648c54d8c6-zpmg5 marked as unschedulable can be scheduled on node template-node-for-eks-managed-ng-1-04beb65b-308f-11f3-e139-b0ebbe48a090-4548432111829895923-1. Ignoring in scale up.
I1129 17:43:53.293201       1 filter_out_schedulable.go:157] Pod default.pasue-deployment-648c54d8c6-s8qcm marked as unschedulable can be scheduled on node template-node-for-eks-managed-ng-1-04beb65b-308f-11f3-e139-b0ebbe48a090-4548432111829895923-1. Ignoring in scale up.
I1129 17:43:53.293209       1 filter_out_schedulable.go:170] 0 pods were kept as unschedulable based on caching
I1129 17:43:53.293216       1 filter_out_schedulable.go:171] 6 pods marked as unschedulable can be scheduled.
I1129 17:43:53.293234       1 filter_out_schedulable.go:79] Schedulable pods present
I1129 17:43:53.293257       1 static_autoscaler.go:401] No unschedulable pods
I1129 17:43:53.293279       1 static_autoscaler.go:448] Calculating unneeded nodes
I1129 17:43:53.293356       1 scale_down.go:447] Node ip-192-168-3-25.eu-west-1.compute.internal - cpu utilization 0.102041
I1129 17:43:53.293385       1 scale_down.go:447] Node ip-192-168-31-113.eu-west-1.compute.internal - cpu utilization 0.102041
I1129 17:43:53.293401       1 scale_down.go:508] Scale-down calculation: ignoring 3 nodes unremovable in the last 5m0s
I1129 17:43:53.293516       1 static_autoscaler.go:491] ip-192-168-3-25.eu-west-1.compute.internal is unneeded since 2021-11-29 17:43:42.944989763 +0000 UTC m=+61.837345699 duration 10.32542882s
I1129 17:43:53.293537       1 static_autoscaler.go:491] ip-192-168-31-113.eu-west-1.compute.internal is unneeded since 2021-11-29 17:43:42.944989763 +0000 UTC m=+61.837345699 duration 10.32542882s
I1129 17:43:53.293554       1 static_autoscaler.go:502] Scale down status: unneededOnly=true lastScaleUpTime=2021-11-29 17:43:02.702663909 +0000 UTC m=+21.595019844 lastScaleDownDeleteTime=2021-11-29 17:42:42.673088267 +0000 UTC m=+1.565444188 lastScaleDownFailTime=2021-11-29 17:42:42.673088334 +0000 UTC m=+1.565444256 scaleDownForbidden=true isDeleteInProgress=false scaleDownInCooldown=true
I1129 17:44:03.332155       1 static_autoscaler.go:228] Starting main loop
I1129 17:44:03.333608       1 filter_out_schedulable.go:65] Filtering out schedulables
I1129 17:44:03.333641       1 filter_out_schedulable.go:132] Filtered out 0 pods using hints
I1129 17:44:03.334074       1 filter_out_schedulable.go:157] Pod default.pasue-deployment-648c54d8c6-498tx marked as unschedulable can be scheduled on node ip-192-168-31-113.eu-west-1.compute.internal. Ignoring in scale up.
I1129 17:44:03.334135       1 filter_out_schedulable.go:157] Pod default.pasue-deployment-648c54d8c6-sl7mb marked as unschedulable can be scheduled on node template-node-for-eks-managed-ng-1-04beb65b-308f-11f3-e139-b0ebbe48a090-8549944162621642512-0. Ignoring in scale up.
I1129 17:44:03.334209       1 filter_out_schedulable.go:170] 0 pods were kept as unschedulable based on caching
I1129 17:44:03.334226       1 filter_out_schedulable.go:171] 2 pods marked as unschedulable can be scheduled.
I1129 17:44:03.334269       1 filter_out_schedulable.go:79] Schedulable pods present
I1129 17:44:03.334300       1 static_autoscaler.go:401] No unschedulable pods
I1129 17:44:03.334319       1 static_autoscaler.go:448] Calculating unneeded nodes
I1129 17:44:03.334411       1 scale_down.go:443] Node ip-192-168-3-25.eu-west-1.compute.internal is not suitable for removal - memory utilization too big (0.989735)
I1129 17:44:03.334457       1 scale_down.go:447] Node ip-192-168-31-113.eu-west-1.compute.internal - memory utilization 0.300287
I1129 17:44:03.334505       1 scale_down.go:508] Scale-down calculation: ignoring 3 nodes unremovable in the last 5m0s
I1129 17:44:03.334578       1 cluster.go:148] Fast evaluation: ip-192-168-31-113.eu-west-1.compute.internal for removal
I1129 17:44:03.334761       1 cluster.go:192] Fast evaluation: node ip-192-168-31-113.eu-west-1.compute.internal is not suitable for removal: failed to find place for default/pasue-deployment-648c54d8c6-498tx
I1129 17:44:03.334810       1 scale_down.go:612] 1 nodes found to be unremovable in simulation, will re-check them at 2021-11-29 17:49:03.332119893 +0000 UTC m=+382.224475909
I1129 17:44:03.334891       1 static_autoscaler.go:502] Scale down status: unneededOnly=true lastScaleUpTime=2021-11-29 17:43:02.702663909 +0000 UTC m=+21.595019844 lastScaleDownDeleteTime=2021-11-29 17:42:42.673088267 +0000 UTC m=+1.565444188 lastScaleDownFailTime=2021-11-29 17:42:42.673088334 +0000 UTC m=+1.565444256 scaleDownForbidden=true isDeleteInProgress=false scaleDownInCooldown=true
```

The `cluster-autoscaler` should start one more node after some time:

```bash
kubectl get nodes -L node.kubernetes.io/instance-type -L topology.kubernetes.io/zone
```

Output:

```text
NAME                                           STATUS   ROLES    AGE     VERSION   INSTANCE-TYPE   ZONE
ip-192-168-3-25.eu-west-1.compute.internal     Ready    <none>   2m10s   v1.21.6   t3.xlarge       eu-west-1a
ip-192-168-31-11.eu-west-1.compute.internal    Ready    <none>   23m     v1.21.6   t3.xlarge       eu-west-1a
ip-192-168-31-113.eu-west-1.compute.internal   Ready    <none>   2m4s    v1.21.6   t3.xlarge       eu-west-1a
ip-192-168-56-82.eu-west-1.compute.internal    Ready    <none>   23m     v1.21.6   t3.xlarge       eu-west-1b
ip-192-168-60-184.eu-west-1.compute.internal   Ready    <none>   23m     v1.21.6   t3.xlarge       eu-west-1b
```

All pods should be running now and some of them are are on the new node:

```bash
kubectl get pods -o wide
```

Output:

```text
NAME                                READY   STATUS    RESTARTS   AGE     IP               NODE                                           NOMINATED NODE   READINESS GATES
pasue-deployment-648c54d8c6-498tx   1/1     Running   0          2m53s   172.16.72.1      ip-192-168-31-113.eu-west-1.compute.internal   <none>           <none>
pasue-deployment-648c54d8c6-4wr5f   1/1     Running   0          2m54s   172.16.166.146   ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-579dx   1/1     Running   0          2m53s   172.16.2.147     ip-192-168-31-11.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-5vqrr   1/1     Running   0          2m53s   172.16.3.89      ip-192-168-60-184.eu-west-1.compute.internal   <none>           <none>
pasue-deployment-648c54d8c6-5zr8k   1/1     Running   0          2m53s   172.16.166.147   ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-7kd65   1/1     Running   0          2m53s   172.16.190.8     ip-192-168-3-25.eu-west-1.compute.internal     <none>           <none>
pasue-deployment-648c54d8c6-kknlr   1/1     Running   0          2m53s   172.16.3.88      ip-192-168-60-184.eu-west-1.compute.internal   <none>           <none>
pasue-deployment-648c54d8c6-pcsb8   1/1     Running   0          2m53s   172.16.190.4     ip-192-168-3-25.eu-west-1.compute.internal     <none>           <none>
pasue-deployment-648c54d8c6-qcdpw   1/1     Running   0          2m53s   172.16.2.146     ip-192-168-31-11.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-s8qcm   1/1     Running   0          2m53s   172.16.190.1     ip-192-168-3-25.eu-west-1.compute.internal     <none>           <none>
pasue-deployment-648c54d8c6-sl7mb   1/1     Running   0          2m53s   172.16.72.2      ip-192-168-31-113.eu-west-1.compute.internal   <none>           <none>
pasue-deployment-648c54d8c6-v7b5x   1/1     Running   0          2m54s   172.16.3.87      ip-192-168-60-184.eu-west-1.compute.internal   <none>           <none>
pasue-deployment-648c54d8c6-vmshk   1/1     Running   0          2m54s   172.16.2.145     ip-192-168-31-11.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-zfqfx   1/1     Running   0          2m53s   172.16.166.148   ip-192-168-56-82.eu-west-1.compute.internal    <none>           <none>
pasue-deployment-648c54d8c6-zpmg5   1/1     Running   0          2m53s   172.16.190.5     ip-192-168-3-25.eu-west-1.compute.internal     <none>           <none>
```

If you delete the deployment `autoscaler-demo` the `cluster-autoscaler` will
decrease the number of nodes:

```bash
kubectl delete deployment pasue-deployment
sleep 800
kubectl get nodes -L node.kubernetes.io/instance-type -L topology.kubernetes.io/zone
```

Output:

```text
NAME                                           STATUS                     ROLES    AGE   VERSION   INSTANCE-TYPE   ZONE
ip-192-168-31-11.eu-west-1.compute.internal    Ready                      <none>   37m   v1.21.6   t3.xlarge       eu-west-1a
ip-192-168-31-113.eu-west-1.compute.internal   Ready,SchedulingDisabled   <none>   15m   v1.21.6   t3.xlarge       eu-west-1a
ip-192-168-56-82.eu-west-1.compute.internal    Ready                      <none>   37m   v1.21.6   t3.xlarge       eu-west-1b
ip-192-168-60-184.eu-west-1.compute.internal   Ready                      <none>   37m   v1.21.6   t3.xlarge       eu-west-1b
```

## Descheduler

Install `descheduler`
[helm chart](https://artifacthub.io/packages/helm/descheduler/descheduler)
and modify the
[default values](https://github.com/kubernetes-sigs/descheduler/blob/master/charts/descheduler/values.yaml).

```bash
helm repo add --force-update descheduler https://kubernetes-sigs.github.io/descheduler/
helm upgrade --install --version 0.21.0 --namespace kube-system --values - descheduler descheduler/descheduler << EOF
cronJobApiVersion: "batch/v1beta1"
successfulJobsHistoryLimit: 10
EOF
```

## Rancher

Install `rancher-server`
[helm chart](https://github.com/rancher/rancher/tree/master/chart)
and modify the
[default values](https://github.com/rancher/rancher/blob/master/chart/values.yaml).

```bash
helm repo add --force-update rancher-latest https://releases.rancher.com/server-charts/latest
helm upgrade --install --version 2.5.9 --namespace cattle-system --create-namespace --values - rancher rancher-latest/rancher << EOF
hostname: rancher.${CLUSTER_FQDN}
ingress:
  extraAnnotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  tls:
    source: secret
    # Not working right now
    secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
replicas: 1
EOF
```

Copy the certificate to the secret with name: `tls-rancher-ingress`.
Rancher [helm chart](https://github.com/rancher/rancher/blob/3c54189441fdac08fd4a1b3113216e085004f061/chart/templates/ingress.yaml#L55)
can not use existing secret for TLS ingress :-(
It should be fixed in next helm chart release...

```bash
kubectl get secret -n cattle-system tls-rancher-ingress || kubectl get secret -n cattle-system "ingress-cert-${LETSENCRYPT_ENVIRONMENT}" -o json | jq ".metadata.name=\"tls-rancher-ingress\"" | kubectl apply -f -
```
