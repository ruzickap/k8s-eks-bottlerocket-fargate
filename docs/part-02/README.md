# AWS

Attach the policy to the [pod execution role](https://docs.aws.amazon.com/eks/latest/userguide/pod-execution-role.html)
of your EKS on Fargate cluster:

```bash
FARGATE_POD_EXECUTION_ROLE_ARN=$(eksctl get iamidentitymapping --cluster=${CLUSTER_NAME} -o json | jq -r ".[] | select (.rolearn | contains(\"FargatePodExecutionRole\")) .rolearn")
aws iam attach-role-policy --policy-arn "${CLOUDWATCH_POLICY_ARN}" --role-name "${FARGATE_POD_EXECUTION_ROLE_ARN#*/}"
```

Create the dedicated `aws-observability` namespace and the ConfigMap for Fluent Bit:

```bash
kubectl apply -f - << EOF
kind: Namespace
apiVersion: v1
metadata:
  name: aws-observability
  labels:
    aws-observability: enabled
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: aws-logging
  namespace: aws-observability
data:
  output.conf: |
    [OUTPUT]
        Name cloudwatch_logs
        Match   *
        region ${AWS_DEFAULT_REGION}
        log_group_name /aws/eks/${CLUSTER_FQDN}/logs
        log_stream_prefix fluentbit-
        auto_create_group On
EOF
```

All the Fargate pods should now send the log to CloudWatch...

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

The `aws-for-fluent-bit` will create Log group `/aws/eks/kube1.k8s.mylabs.dev/logs`
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

The `aws-cloudwatch-metrics` populates "Container insights" in CloudWatch...

## aws-efs-csi-driver

Install [Amazon EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver),
which supports ReadWriteMany PVC, is installed.

Install [Amazon EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver)
`aws-efs-csi-driver`
[helm chart](https://github.com/kubernetes-sigs/aws-efs-csi-driver/tree/master/charts/aws-efs-csi-driver)
and modify the
[default values](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/charts/aws-efs-csi-driver/values.yaml):

```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
kubectl delete CSIDriver efs.csi.aws.com
helm install --version 1.1.1 --namespace kube-system aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver
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

Install Amazon EBS CSI Driver `aws-ebs-csi-driver`
[helm chart](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/tree/master/charts/aws-ebs-csi-driver)
and modify the
[default values](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/charts/aws-ebs-csi-driver/values.yaml):
The ServiceAccount `ebs-csi-controller` was created by `eksctl`.

```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm install --version 0.9.8 --namespace kube-system --values - aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver << EOF
enableVolumeScheduling: true
enableVolumeResizing: true
enableVolumeSnapshot: true
k8sTagClusterId: ${CLUSTER_FQDN}
serviceAccount:
  controller:
    create: false
    name: ebs-csi-controller
  snapshot:
    create: false
    name: ebs-csi-controller
  node:
    create: false
    name: ebs-csi-controller
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

## aws-load-balancer-controller

Install `aws-load-balancer-controller`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller)
and modify the
[default values](https://github.com/aws/eks-charts/blob/master/stable/aws-load-balancer-controller/values.yaml).

```bash
helm install --version 1.1.5 --namespace kube-system --values - aws-load-balancer-controller eks/aws-load-balancer-controller << EOF
clusterName: ${CLUSTER_NAME}
serviceAccount:
  create: false
  name: aws-load-balancer-controller
enableShield: false
enableWaf: false
enableWafv2: false
defaultTags:
$(echo "${TAGS}" | sed "s/ /\\n  /g; s/^/  /g; s/=/: /g")
EOF
```

It seems like there are some issues with ALB and cert-manager / Istio:

* [https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/1084](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/1084)
* [https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/1143](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/1143)

I'll use NLB as main "Load Balancer type" in AWS.

## Test Amazon EKS pod limits

By default, there is certain number of pods which can be run on Amazon EKS
worker nodes. The "max number of pods" depends on node type an you can read
about it on these links:

* [https://github.com/awslabs/amazon-eks-ami/blob/master/files/eni-max-pods.txt](https://github.com/awslabs/amazon-eks-ami/blob/master/files/eni-max-pods.txt)
* [Elastic network interfaces](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)
* [Pod limit on Node - AWS EKS](https://stackoverflow.com/questions/57970896/pod-limit-on-node-aws-eks/57971006)

I would like to put some notes here how this can be tested...

Start the EKS cluster with `t2.micro` where you can run max 4 pods per node:

```shell
eksctl create cluster --name test-max-pod --region eu-central-1 --node-type=t2.micro --nodes=2 --node-volume-size=4 --kubeconfig "kubeconfig-test-max-pod.conf" --max-pods-per-node 100
```

Show the limits of the node, which can not be fulfilled due to IP limitations:

```shell
kubectl describe nodes -A | grep "pods:" | uniq
```

Output:

```text
  pods:                        1k
```

Run 3 `nginx` pods:

```shell
kubectl apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml
```

One of them will fail:

```shell
kubectl describe pod
```

Output:

```text
...
  Warning  FailedCreatePodSandBox  33s                 kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to set up sandbox container "738ecb9c495143df8647e69e70d19181643ebda1d3ce5d89e06526cf4285b89d" network for pod "nginx-deployment-6b474476c4-df8rz": networkPlugin cni failed to set up pod "nginx-deployment-6b474476c4-df8rz_default" network: add cmd: failed to assign an IP address to container
...
```

Delete the cluster:

```shell
eksctl delete cluster --name test-max-pod --region eu-central-1
```

Do the same with Amazon EKS + Calico:

```shell
eksctl create cluster --name test-max-pod --region eu-central-1  --without-nodegroup --kubeconfig "kubeconfig-test-max-pod.conf"
kubectl delete daemonset -n kube-system aws-node
kubectl apply -f https://docs.projectcalico.org/manifests/calico-vxlan.yaml
eksctl create nodegroup --cluster test-max-pod --region eu-central-1 --node-type=t2.micro --nodes=2 --node-volume-size=4 --max-pods-per-node 100
kubectl apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml
kubectl scale --replicas=10 deployment nginx-deployment
```

Check the running pods:

```shell
kubectl get pods
```

Output:

```text
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-6b474476c4-26d4x   1/1     Running   0          34s
nginx-deployment-6b474476c4-2nbnc   1/1     Running   0          70s
nginx-deployment-6b474476c4-7cfpn   1/1     Running   0          70s
nginx-deployment-6b474476c4-7wdk4   1/1     Running   0          2m10s
nginx-deployment-6b474476c4-8dhmb   1/1     Running   0          34s
nginx-deployment-6b474476c4-kp8p8   1/1     Running   0          34s
nginx-deployment-6b474476c4-nk699   1/1     Running   0          34s
nginx-deployment-6b474476c4-rk26b   1/1     Running   0          2m10s
nginx-deployment-6b474476c4-x6w29   1/1     Running   0          34s
nginx-deployment-6b474476c4-x8wkv   1/1     Running   0          2m10s
```

It should be possible to run more pods than 4 comparing to "non-calico"
example.

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
