# AWS

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

```bash
helm repo add eks https://aws.github.io/eks-charts
helm install --version 1.1.6 --namespace kube-system --values - aws-load-balancer-controller eks/aws-load-balancer-controller << EOF
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
helm install --version 0.1.7 --namespace kube-system --values - aws-for-fluent-bit eks/aws-for-fluent-bit << EOF
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
helm install --version 0.0.4 --namespace amazon-cloudwatch --create-namespace --values - aws-cloudwatch-metrics eks/aws-cloudwatch-metrics << EOF
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
      GroupName: !Sub "${ClusterName}-efs-sg-groupname"
      GroupDescription: Security group for mount target
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: "2049"
          ToPort: "2049"
          CidrIp:
            Ref: VpcIPCidr
      Tags:
        - Key: Name
          Value: !Sub "${ClusterName}-efs-sg-tagname"
  FileSystem:
    Type: AWS::EFS::FileSystem
    Properties:
      Encrypted: true
      FileSystemTags:
      - Key: Name
        Value: !Sub "${ClusterName}-efs"
      KmsKeyId: !Ref KmsKeyId
  MountTargetAZ1:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId:
        Ref: FileSystem
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
        Ref: FileSystem
      SubnetId:
        Fn::Select:
        - 1
        - Fn::Split:
          - ","
          - Fn::ImportValue: !Sub "eksctl-${ClusterName}-cluster::SubnetsPrivate"
      SecurityGroups:
      - Ref: MountTargetSecurityGroup
  AccessPointDrupal:
    Type: AWS::EFS::AccessPoint
    Properties:
      FileSystemId: !Ref FileSystem
      # Set proper uid/gid: https://github.com/bitnami/bitnami-docker-drupal/blob/02f7e41c88eee96feb90c8b7845ee7aeb5927c38/9/debian-10/Dockerfile#L49
      PosixUser:
        Uid: "1001"
        Gid: "1001"
      RootDirectory:
        CreationInfo:
          OwnerGid: "1001"
          OwnerUid: "1001"
          Permissions: "700"
        Path: "/drupal"
      AccessPointTags:
        - Key: Name
          Value: !Sub "${ClusterName}-drupal-efs-ap"
  AccessPointDrupal2:
    Type: AWS::EFS::AccessPoint
    Properties:
      FileSystemId: !Ref FileSystem
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
          Value: !Sub "${ClusterName}-drupal2-efs-ap"
Outputs:
  FileSystemId:
    Description: Id of Elastic File System
    Value:
      Ref: FileSystem
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-FileSystemId"
  AccessPointDrupal:
    Description: EFS AccessPoint ID for Drupal
    Value:
      Ref: AccessPointDrupal
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-AccessPointDrupal"
  AccessPointDrupal2:
    Description: EFS AccessPoint2 ID for Drupal2
    Value:
      Ref: AccessPointDrupal2
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-AccessPointDrupal2"
EOF

eval aws cloudformation deploy --stack-name "${CLUSTER_NAME}-efs" --parameter-overrides "ClusterName=${CLUSTER_NAME} KmsKeyId=${EKS_KMS_KEY_ID} VpcIPCidr=${EKS_VPC_CIDR}" --template-file "tmp/${CLUSTER_FQDN}/cf_efs.yml" --tags "${TAGS}"

EFS_FS_ID=$(aws efs describe-file-systems --query "FileSystems[?Name==\`${CLUSTER_NAME}-efs\`].[FileSystemId]" --output text)
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
helm install --version 1.2.2 --namespace kube-system --values - aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver << EOF
serviceAccount:
  controller:
    create: false
storageClasses:
- name: efs-dynamic-sc
  parameters:
    provisioningMode: efs-ap
    fileSystemId: "${EFS_FS_ID}"
    directoryPerms: "700"
    basePath: "/dynamic_provisioning"
EOF
```

Create storage class for static EFS:

```bash
kubectl apply -f - << EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-static-sc
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
helm install --version 0.10.2 --namespace kube-system --values - aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver << EOF
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
