# AWS

Add EKS helm repository:

```bash
helm repo add eks https://aws.github.io/eks-charts
```

## Fargate

Attach the policy to the [pod execution role](https://docs.aws.amazon.com/eks/latest/userguide/pod-execution-role.html)
of your EKS on Fargate cluster:

```shell
FARGATE_POD_EXECUTION_ROLE_ARN=$(eksctl get iamidentitymapping --cluster="${CLUSTER_NAME}" -o json | jq -r ".[] | select (.rolearn | contains(\"FargatePodExecutionRole\")) .rolearn")
aws iam attach-role-policy --policy-arn "${CLOUDWATCH_POLICY_ARN}" --role-name "${FARGATE_POD_EXECUTION_ROLE_ARN#*/}"
```

Create the dedicated `aws-observability` namespace and the ConfigMap for Fluent Bit:

```shell
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

## aws-load-balancer-controller

Install `aws-load-balancer-controller`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller)
and modify the
[default values](https://github.com/aws/eks-charts/blob/master/stable/aws-load-balancer-controller/values.yaml).

```shell
helm upgrade --install --version 1.2.0 --namespace kube-system --values - aws-load-balancer-controller eks/aws-load-balancer-controller << EOF
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

## aws-for-fluent-bit

Install `aws-for-fluent-bit`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-for-fluent-bit)
and modify the
[default values](https://github.com/aws/eks-charts/blob/master/stable/aws-for-fluent-bit/values.yaml).

```shell
helm upgrade --install --version 0.1.11 --namespace kube-system --values - aws-for-fluent-bit eks/aws-for-fluent-bit << EOF
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

```shell
helm upgrade --install --version 0.0.5 --namespace amazon-cloudwatch --create-namespace --values - aws-cloudwatch-metrics eks/aws-cloudwatch-metrics << EOF
clusterName: ${CLUSTER_FQDN}
EOF
```

The `aws-cloudwatch-metrics` populates "Container insights" in CloudWatch...

## aws-efs-csi-driver

Get the details about the VPC to be able to configure security groups for EFS:

```bash
EKS_VPC_ID=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text)
EKS_VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "${EKS_VPC_ID}" --query "Vpcs[].CidrBlock" --output text)
```

Create EFS using CloudFormation:

Apply CloudFormation template to create Amazon EFS.
The template below is inspired by: [https://github.com/so008mo/inkubator-play/blob/64a150dbdc35b9ade48ff21b9ae6ba2710d18b5d/roles/eks/files/amazon-eks-efs.yaml](https://github.com/so008mo/inkubator-play/blob/64a150dbdc35b9ade48ff21b9ae6ba2710d18b5d/roles/eks/files/amazon-eks-efs.yaml)

```bash
cat > "tmp/${CLUSTER_FQDN}/cf_efs.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Create EFS, mount points, security groups for EKS
Parameters:
  ClusterName:
    Description: "K8s Cluster name. Ex: kube1"
    Type: String
  KmsKeyId:
    Description: The ID of the AWS KMS customer master key (CMK) to be used to protect the encrypted file system
    Type: String
  VpcIPCidr:
    Description: "Enter VPC CIDR that hosts the EKS cluster. Ex: 10.0.0.0/16"
    Type: String
Resources:
  MountTargetSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      VpcId:
        Fn::ImportValue:
          Fn::Sub: "eksctl-${ClusterName}-cluster::VPC"
      GroupName: !Sub "${ClusterName}-efs-sg"
      GroupDescription: Security group for mount target
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: "2049"
          ToPort: "2049"
          CidrIp:
            Ref: VpcIPCidr
      Tags:
        - Key: Name
          Value: !Sub "${ClusterName}-efs-sg"
  FileSystemDrupal:
    Type: AWS::EFS::FileSystem
    Properties:
      Encrypted: true
      FileSystemTags:
      - Key: Name
        Value: !Sub "${ClusterName}-efs-drupal"
      KmsKeyId: !Ref KmsKeyId
  MountTargetAZ1:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId:
        Ref: FileSystemDrupal
      SubnetId:
        Fn::Select:
        - 0
        - Fn::Split:
          - ","
          - Fn::ImportValue: !Sub "eksctl-${ClusterName}-cluster::SubnetsPrivate"
      SecurityGroups:
      - Ref: MountTargetSecurityGroup
  MountTargetAZ2:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId:
        Ref: FileSystemDrupal
      SubnetId:
        Fn::Select:
        - 1
        - Fn::Split:
          - ","
          - Fn::ImportValue: !Sub "eksctl-${ClusterName}-cluster::SubnetsPrivate"
      SecurityGroups:
      - Ref: MountTargetSecurityGroup
  AccessPointDrupal1:
    Type: AWS::EFS::AccessPoint
    Properties:
      FileSystemId: !Ref FileSystemDrupal
      # Set proper uid/gid: https://github.com/bitnami/bitnami-docker-drupal/blob/02f7e41c88eee96feb90c8b7845ee7aeb5927c38/9/debian-10/Dockerfile#L49
      PosixUser:
        Uid: "1001"
        Gid: "1001"
      RootDirectory:
        CreationInfo:
          OwnerGid: "1001"
          OwnerUid: "1001"
          Permissions: "700"
        Path: "/drupal1"
      AccessPointTags:
        - Key: Name
          Value: !Sub "${ClusterName}-drupal1-ap"
  AccessPointDrupal2:
    Type: AWS::EFS::AccessPoint
    Properties:
      FileSystemId: !Ref FileSystemDrupal
      # Set proper uid/gid: https://github.com/bitnami/bitnami-docker-drupal/blob/02f7e41c88eee96feb90c8b7845ee7aeb5927c38/9/debian-10/Dockerfile#L49
      PosixUser:
        Uid: "1001"
        Gid: "1001"
      RootDirectory:
        CreationInfo:
          OwnerGid: "1001"
          OwnerUid: "1001"
          Permissions: "700"
        Path: "/drupal2"
      AccessPointTags:
        - Key: Name
          Value: !Sub "${ClusterName}-drupal2-ap"
  FileSystemMyuser1:
    Type: AWS::EFS::FileSystem
    Properties:
      Encrypted: true
      FileSystemTags:
      - Key: Name
        Value: !Sub "${ClusterName}-myuser1"
      KmsKeyId: !Ref KmsKeyId
  MountTargetAZ1Myuser1:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId:
        Ref: FileSystemMyuser1
      SubnetId:
        Fn::Select:
        - 0
        - Fn::Split:
          - ","
          - Fn::ImportValue: !Sub "eksctl-${ClusterName}-cluster::SubnetsPrivate"
      SecurityGroups:
      - Ref: MountTargetSecurityGroup
  MountTargetAZ2Myuser1:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId:
        Ref: FileSystemMyuser1
      SubnetId:
        Fn::Select:
        - 1
        - Fn::Split:
          - ","
          - Fn::ImportValue: !Sub "eksctl-${ClusterName}-cluster::SubnetsPrivate"
      SecurityGroups:
      - Ref: MountTargetSecurityGroup
  AccessPointMyuser1:
    Type: AWS::EFS::AccessPoint
    Properties:
      FileSystemId: !Ref FileSystemMyuser1
      # Set proper uid/gid: https://github.com/bitnami/bitnami-docker-drupal/blob/02f7e41c88eee96feb90c8b7845ee7aeb5927c38/9/debian-10/Dockerfile#L49
      RootDirectory:
        Path: "/myuser1"
      AccessPointTags:
        - Key: Name
          Value: !Sub "${ClusterName}-myuser1"
  FileSystemMyuser2:
    Type: AWS::EFS::FileSystem
    Properties:
      Encrypted: true
      FileSystemTags:
      - Key: Name
        Value: !Sub "${ClusterName}-Myuser2"
      KmsKeyId: !Ref KmsKeyId
  MountTargetAZ1Myuser2:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId:
        Ref: FileSystemMyuser2
      SubnetId:
        Fn::Select:
        - 0
        - Fn::Split:
          - ","
          - Fn::ImportValue: !Sub "eksctl-${ClusterName}-cluster::SubnetsPrivate"
      SecurityGroups:
      - Ref: MountTargetSecurityGroup
  MountTargetAZ2Myuser2:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId:
        Ref: FileSystemMyuser2
      SubnetId:
        Fn::Select:
        - 1
        - Fn::Split:
          - ","
          - Fn::ImportValue: !Sub "eksctl-${ClusterName}-cluster::SubnetsPrivate"
      SecurityGroups:
      - Ref: MountTargetSecurityGroup
  AccessPointMyuser2:
    Type: AWS::EFS::AccessPoint
    Properties:
      FileSystemId: !Ref FileSystemMyuser2
      # Set proper uid/gid: https://github.com/bitnami/bitnami-docker-drupal/blob/02f7e41c88eee96feb90c8b7845ee7aeb5927c38/9/debian-10/Dockerfile#L49
      RootDirectory:
        Path: "/myuser2"
      AccessPointTags:
        - Key: Name
          Value: !Sub "${ClusterName}-myuser2"
Outputs:
  FileSystemIdDrupal:
    Description: Id of Elastic File System
    Value:
      Ref: FileSystemDrupal
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-FileSystemIdDrupal"
  AccessPointIdDrupal1:
    Description: EFS AccessPoint ID for Drupal1
    Value:
      Ref: AccessPointDrupal1
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-AccessPointIdDrupal1"
  AccessPointIdDrupal2:
    Description: EFS AccessPoint2 ID for Drupal2
    Value:
      Ref: AccessPointDrupal2
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-AccessPointIdDrupal2"
  FileSystemIdMyuser1:
    Description: Id of Elastic File System Myuser1
    Value:
      Ref: FileSystemMyuser1
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-FileSystemIdMyuser1"
  AccessPointIdMyuser1:
    Description: EFS AccessPoint2 ID for Myuser1
    Value:
      Ref: AccessPointMyuser1
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-AccessPointIdMyuser1"
  FileSystemIdMyuser2:
    Description: ID of Elastic File System Myuser2
    Value:
      Ref: FileSystemMyuser2
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-FileSystemIdMyuser2"
  AccessPointIdMyuser2:
    Description: EFS AccessPoint2 ID for Myuser2
    Value:
      Ref: AccessPointMyuser2
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-AccessPointIdMyuser2"
EOF

eval aws cloudformation deploy --stack-name "${CLUSTER_NAME}-efs" --parameter-overrides "ClusterName=${CLUSTER_NAME} KmsKeyId=${KMS_KEY_ID} VpcIPCidr=${EKS_VPC_CIDR}" --template-file "tmp/${CLUSTER_FQDN}/cf_efs.yml" --tags "${TAGS}"

AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-efs")
EFS_FS_ID_DRUPAL=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"FileSystemIdDrupal\") .OutputValue")
EFS_AP_ID_DRUPAL1=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"AccessPointIdDrupal1\") .OutputValue")
EFS_AP_ID_DRUPAL2=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"AccessPointIdDrupal2\") .OutputValue")
EFS_FS_ID_MYUSER1=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"FileSystemIdMyuser1\") .OutputValue")
EFS_AP_ID_MYUSER1=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"AccessPointIdMyuser1\") .OutputValue")
EFS_FS_ID_MYUSER2=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"FileSystemIdMyuser2\") .OutputValue")
EFS_AP_ID_MYUSER2=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"AccessPointIdMyuser2\") .OutputValue")
```

Install [Amazon EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver),
which supports ReadWriteMany PVC. Details can be found here:
[Introducing Amazon EFS CSI dynamic provisioning](https://aws.amazon.com/blogs/containers/introducing-efs-csi-dynamic-provisioning/)

Install [Amazon EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver)
`aws-efs-csi-driver`
[helm chart](https://github.com/kubernetes-sigs/aws-efs-csi-driver/tree/master/charts/aws-efs-csi-driver)
and modify the
[default values](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/charts/aws-efs-csi-driver/values.yaml):

```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm upgrade --install --version 2.1.1 --namespace kube-system --values - aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver << EOF
controller:
  serviceAccount:
    create: false
storageClasses:
- name: efs-drupal-dynamic
  mountOptions:
  - tls
  parameters:
    provisioningMode: efs-ap
    fileSystemId: "${EFS_FS_ID_DRUPAL}"
    directoryPerms: "700"
    basePath: "/dynamic_provisioning"
  reclaimPolicy: Delete
- name: efs-drupal-static
  mountOptions:
  - tls
  parameters:
    provisioningMode: efs-ap
    fileSystemId: "${EFS_FS_ID_DRUPAL}"
    directoryPerms: "700"
  reclaimPolicy: Delete
- name: efs-myuser1
  mountOptions:
  - tls
  parameters:
    provisioningMode: efs-ap
    fileSystemId: "${EFS_FS_ID_MYUSER1}"
    directoryPerms: "700"
  reclaimPolicy: Delete
- name: efs-myuser2
  mountOptions:
  - tls
  parameters:
    provisioningMode: efs-ap
    fileSystemId: "${EFS_FS_ID_MYUSER2}"
    directoryPerms: "700"
  reclaimPolicy: Delete
EOF
```

Create `PersistentVolume`s which can be consumed by users (`myuser1`, `myuser2`)
using `PersistentVolumeClaim`:

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-myuser1
spec:
  storageClassName: efs-myuser1
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Delete
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FS_ID_MYUSER1}::${EFS_AP_ID_MYUSER1}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-myuser2
spec:
  storageClassName: efs-myuser2
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Delete
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FS_ID_MYUSER2}::${EFS_AP_ID_MYUSER2}
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
helm upgrade --install --version 1.2.3 --namespace kube-system --values - aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver << EOF
enableVolumeScheduling: true
enableVolumeResizing: true
enableVolumeSnapshot: true
k8sTagClusterId: ${CLUSTER_FQDN}
controller:
  extraVolumeTags:
  $(echo "${TAGS}" | sed "s/ /\\n    /g; s/^/  /g; s/=/: /g")
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
storageClasses:
- name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
  parameters:
    type: "gp3"
    encrypted: "true"
EOF
```

Unset `gp2` as default StorageClass annotation:

```bash
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
apiVersion: snapshot.storage.k8s.io/v1
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
eksctl create cluster --name test-max-pod --region ${AWS_DEFAULT_REGION} --node-type=t2.micro --nodes=2 --node-volume-size=4 --kubeconfig "kubeconfig-test-max-pod.conf" --max-pods-per-node 100
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
eksctl delete cluster --name test-max-pod --region ${AWS_DEFAULT_REGION}
```

Do the same with Amazon EKS + Calico:

```shell
eksctl create cluster --name test-max-pod --region ${AWS_DEFAULT_REGION}  --without-nodegroup --kubeconfig "kubeconfig-test-max-pod.conf"
kubectl delete daemonset -n kube-system aws-node
kubectl apply -f https://docs.projectcalico.org/manifests/calico-vxlan.yaml
eksctl create nodegroup --cluster test-max-pod --region ${AWS_DEFAULT_REGION} --node-type=t2.micro --nodes=2 --node-volume-size=4 --max-pods-per-node 100
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

## Amazon Managed Prometheus + Amazon Managed Grafana

Create AMP Workspace

```bash
if ! aws amp list-workspaces | grep -q "${CLUSTER_FQDN}" ; then aws amp create-workspace --alias="${CLUSTER_FQDN}" | jq ; fi
AMP_WORKSPACE_ID=$(aws amp list-workspaces --alias "${CLUSTER_FQDN}" | jq -r ".workspaces[0].workspaceId")
```

Output:

```json
{
    "arn": "arn:aws:aps:eu-central-1:7xxxxxxxxxx7:workspace/ws-655f1f62-f1f3-4a1c-a35a-219af833c5ab",
    "status": {
        "statusCode": "CREATING"
    },
    "workspaceId": "ws-655f1f62-f1f3-4a1c-a35a-219af833c5ab"
}
```

## Test EKS access

Update the aws-auth ConfigMap to allow our IAM roles:

```bash
eksctl get iamidentitymapping --cluster="${CLUSTER_NAME}" --arn="${MYUSER1_ROLE_ARN}" || eksctl create iamidentitymapping --cluster="${CLUSTER_NAME}" --arn="${MYUSER1_ROLE_ARN}" --username myuser1 --group capsule.clastix.io
eksctl get iamidentitymapping --cluster="${CLUSTER_NAME}" --arn="${MYUSER2_ROLE_ARN}" || eksctl create iamidentitymapping --cluster="${CLUSTER_NAME}" --arn="${MYUSER2_ROLE_ARN}" --username myuser2 --group capsule.clastix.io
eksctl get iamidentitymapping --cluster="${CLUSTER_NAME}"
```

Output:

```text
ARN                       USERNAME        GROUPS
arn:aws:iam::7xxxxxxxxxxxx7:role/AVM-OIDC-ADMIN             admin         system:masters
arn:aws:iam::7xxxxxxxxxxxx7:role/eksctl-kube1-cluster-FargatePodExecutionRole-V6D382FKHGRL  system:node:{{SessionName}}   system:bootstrappers,system:nodes,system:node-proxier
arn:aws:iam::7xxxxxxxxxxxx7:role/eksctl-kube1-nodegroup-managed-ng-NodeInstanceRole-BUBT3FN0WIJS  system:node:{{EC2PrivateDNSName}} system:bootstrappers,system:nodes
arn:aws:iam::7xxxxxxxxxxxx7:role/myuser1-kube1              myuser1         capsule.clastix.io
arn:aws:iam::7xxxxxxxxxxxx7:role/myuser2-kube1              myuser2         capsule.clastix.io
```

Create `config` and `credentials` files and set the environment variables
for `awscli`:

```bash
cat > "tmp/${CLUSTER_FQDN}/aws_config" << EOF
[profile myuser1]
role_arn=${MYUSER1_ROLE_ARN}
source_profile=myuser1

[profile myuser2]
role_arn=${MYUSER2_ROLE_ARN}
source_profile=myuser2
EOF

cat > "tmp/${CLUSTER_FQDN}/aws_credentials" << EOF
[myuser1]
aws_access_key_id=${MYUSER1_USER_ACCESSKEYMYUSER}
aws_secret_access_key=${MYUSER1_USER_SECRETACCESSKEY}

[myuser2]
aws_access_key_id=${MYUSER2_USER_ACCESSKEYMYUSER}
aws_secret_access_key=${MYUSER2_USER_SECRETACCESSKEY}
EOF
```

Extract `kubeconfig` and make it usable for dev profile:

```bash
if [[ ! -f "tmp/${CLUSTER_FQDN}/kubeconfig-myuser1.conf" ]]; then
  eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig="tmp/${CLUSTER_FQDN}/kubeconfig-myuser1.conf"
  cp -f "tmp/${CLUSTER_FQDN}/kubeconfig-myuser1.conf" "tmp/${CLUSTER_FQDN}/kubeconfig-myuser2.conf"
  cat >> "tmp/${CLUSTER_FQDN}/kubeconfig-myuser1.conf" << EOF
      - name: AWS_PROFILE
        value: myuser1
      - name: AWS_CONFIG_FILE
        value: ${PWD}/tmp/${CLUSTER_FQDN}/aws_config
      - name: AWS_SHARED_CREDENTIALS_FILE
        value: ${PWD}/tmp/${CLUSTER_FQDN}/aws_credentials
EOF
  cat >> "tmp/${CLUSTER_FQDN}/kubeconfig-myuser2.conf" << EOF
      - name: AWS_PROFILE
        value: myuser2
      - name: AWS_CONFIG_FILE
        value: ${PWD}/tmp/${CLUSTER_FQDN}/aws_config
      - name: AWS_SHARED_CREDENTIALS_FILE
        value: ${PWD}/tmp/${CLUSTER_FQDN}/aws_credentials
EOF
fi
```

Set the AWS variables and verify the identity:

```bash
env -i bash << EOF
export AWS_CONFIG_FILE="tmp/${CLUSTER_FQDN}/aws_config"
export AWS_SHARED_CREDENTIALS_FILE="tmp/${CLUSTER_FQDN}/aws_credentials"
export PATH="/usr/local/bin:\${PATH}"
aws sts get-caller-identity --profile=myuser1 | jq
aws sts get-caller-identity --profile=myuser2 | jq
EOF
```

Output:

```json
{
  "UserId": "AROA2TXJQ2JHRZM5JQPOL:botocore-session-1624817597",
  "Account": "7xxxxxxxxxxxx7",
  "Arn": "arn:aws:sts::7xxxxxxxxxxxx7:assumed-role/myuser1-kube1/botocore-session-1624817597"
}
{
  "UserId": "AROA2TXJQ2JH4OJAVYJD5:botocore-session-1624817602",
  "Account": "7xxxxxxxxxxxx7",
  "Arn": "arn:aws:sts::7xxxxxxxxxxxx7:assumed-role/myuser2-kube1/botocore-session-1624817602"
}
```

## Capsule

Install Capsule
[helm chart](https://github.com/clastix/capsule/tree/master/charts/capsule)
and modify the
[default values](https://github.com/clastix/capsule/blob/master/charts/capsule/values.yaml):

```bash
helm repo add clastix https://clastix.github.io/charts
helm upgrade --install --version 0.0.19 --namespace capsule-system --create-namespace --wait --values - capsule clastix/capsule << EOF
serviceMonitor:
  enabled: true
EOF
sleep 20
```

```bash
kubectl apply -f - << EOF
apiVersion: capsule.clastix.io/v1alpha1
kind: Tenant
metadata:
  name: myuser1
  namespace: capsule-system
spec:
  namespaceQuota: 1
  owner:
    kind: User
    name: myuser1
  limitRanges:
    -
      limits:
        -
          max:
            storage: 10Gi
          min:
            storage: 1Gi
          type: PersistentVolumeClaim
  storageClasses:
    allowed:
      - efs-myuser1
---
apiVersion: capsule.clastix.io/v1alpha1
kind: Tenant
metadata:
  name: myuser2
  namespace: capsule-system
spec:
  namespaceQuota: 1
  owner:
    kind: User
    name: myuser2
  limitRanges:
    -
      limits:
        -
          max:
            storage: 10Gi
          min:
            storage: 1Gi
          type: PersistentVolumeClaim
  storageClasses:
    allowed:
      - efs-myuser2
EOF
```

```bash
env -i bash << EOF2
set -x
export PATH="/usr/local/bin:\${PATH}"
export KUBECONFIG="tmp/${CLUSTER_FQDN}/kubeconfig-myuser1.conf"

kubectl create namespace myuser1  || true
kubectl get pods -n myuser1
kubectl get pods -n default  || true
kubectl get namespace  || true
kubectl get storageclass  || true

# This is working fine
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myuser1-efs-pvc
  namespace: myuser1
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-myuser1
  volumeName: efs-myuser1
  resources:
    requests:
      storage: 1Gi
EOF

# This will not work because of StorageClass efs-myuser2 can not be used by this tenant
kubectl apply -f - << EOF || true
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myuser1-2-efs-pvc
  namespace: myuser1
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-myuser2
  volumeName: efs-myuser2
  resources:
    requests:
      storage: 1Gi
EOF
EOF2
```

Output:

```text
+ export PATH=/usr/local/bin:/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.
+ PATH=/usr/local/bin:/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.
+ export KUBECONFIG=tmp/kube1.k8s.mylabs.dev/kubeconfig-myuser1.conf
+ KUBECONFIG=tmp/kube1.k8s.mylabs.dev/kubeconfig-myuser1.conf
+ kubectl create namespace myuser1
namespace/myuser1 created
+ kubectl get pods -n myuser1
No resources found in myuser1 namespace.
+ kubectl get pods -n default
Error from server (Forbidden): pods is forbidden: User "myuser1" cannot list resource "pods" in API group "" in the namespace "default"
+ true
+ kubectl get namespace
Error from server (Forbidden): namespaces is forbidden: User "myuser1" cannot list resource "namespaces" in API group "" at the cluster scope
+ true
+ kubectl get storageclass
Error from server (Forbidden): storageclasses.storage.k8s.io is forbidden: User "myuser1" cannot list resource "storageclasses" in API group "storage.k8s.io" at the cluster scope
+ true
+ kubectl apply -f -
persistentvolumeclaim/myuser1-efs-pvc created
+ kubectl apply -f -
Error from server: error when creating "STDIN": admission webhook "pvc.capsule.clastix.io" denied the request: Storage Class efs-myuser2 is forbidden for the current Tenant, one of the following (efs-myuser1)
+ true
```
