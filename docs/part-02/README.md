# AWS

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

## aws-node-termination-handler

Install [AWS Node Termination Handler](https://github.com/aws/aws-node-termination-handler)
which gracefully handle EC2 instance shutdown within Kubernetes.
This may happen when one of the K8s workers needs to be replaced by scheduling
the event: [https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-instances-status-check_sched.html](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-instances-status-check_sched.html)

Install `aws-node-termination-handler`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-node-termination-handler)
and modify the
[default values](https://github.com/aws/aws-node-termination-handler/blob/main/config/helm/aws-node-termination-handler/values.yaml).

```bash
helm install --version 0.13.2 --namespace kube-system --create-namespace --values - aws-node-termination-handler eks/aws-node-termination-handler << EOF
enableRebalanceMonitoring: true
awsRegion: ${AWS_DEFAULT_REGION}
enableSpotInterruptionDraining: true
enableScheduledEventDraining: true
deleteLocalData: true
EOF
```

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
helm install --version 1.1.0 --namespace kube-system aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver
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
