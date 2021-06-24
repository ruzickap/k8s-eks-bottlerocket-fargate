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

eval aws cloudformation deploy --stack-name "${CLUSTER_NAME}-efs" --parameter-overrides "ClusterName=${CLUSTER_NAME} KmsKeyId=${KMS_KEY_ID} VpcIPCidr=${EKS_VPC_CIDR}" --template-file "tmp/${CLUSTER_FQDN}/cf_efs.yml" --tags "${TAGS}"

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
helm upgrade --install --version 2.1.1 --namespace kube-system --values - aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver << EOF
controller:
  serviceAccount:
    create: false
storageClasses:
- name: efs-dynamic-sc
  mountOptions:
  - tls
  parameters:
    provisioningMode: efs-ap
    fileSystemId: "${EFS_FS_ID}"
    directoryPerms: "700"
    basePath: "/dynamic_provisioning"
  reclaimPolicy: Delete
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

```shell
eksctl create iamidentitymapping --cluster="${CLUSTER_NAME}" --arn="${MYUSER1_ROLE_ARN}" --username dev-user
eksctl get iamidentitymapping --cluster="${CLUSTER_NAME}"
```

Output:

```text
2021-06-23 23:17:04 [ℹ]  eksctl version 0.54.0
2021-06-23 23:17:04 [ℹ]  using region eu-west-1
2021-06-23 23:17:05 [ℹ]  adding identity "arn:aws:iam::7xxxxxxxxxx7:role/myuser1-kube1" to auth ConfigMap
2021-06-23 23:17:06 [ℹ]  eksctl version 0.54.0
2021-06-23 23:17:06 [ℹ]  using region eu-west-1
ARN                       USERNAME        GROUPS
arn:aws:iam::7xxxxxxxxxx7:role/Axx-xxxx-xxxxN             admin         system:masters
arn:aws:iam::7xxxxxxxxxx7:role/eksctl-kube1-cluster-FargatePodExecutionRole-1FSA35DMJOZBB system:node:{{SessionName}}   system:bootstrappers,system:nodes,system:node-proxier
arn:aws:iam::7xxxxxxxxxx7:role/eksctl-kube1-nodegroup-managed-ng-NodeInstanceRole-1GSZHWOPAQAOM system:node:{{EC2PrivateDNSName}} system:bootstrappers,system:nodes
arn:aws:iam::7xxxxxxxxxx7:role/myuser1-kube1              dev-user
```

Configuring access to development namespace:

```shell
kubectl get namespace development &> /dev/null || kubectl create namespace development
kubectl apply -f - << EOF
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: dev-role
  namespace: development
rules:
  - apiGroups:
      - ""
      - "apps"
      - "batch"
      - "extensions"
    resources:
      - "configmaps"
      - "cronjobs"
      - "deployments"
      - "events"
      - "ingresses"
      - "jobs"
      - "pods"
      - "pods/attach"
      - "pods/exec"
      - "pods/log"
      - "pods/portforward"
      - "secrets"
      - "services"
    verbs:
      - "create"
      - "delete"
      - "describe"
      - "get"
      - "list"
      - "patch"
      - "update"
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: dev-role-binding
  namespace: development
subjects:
- kind: User
  name: dev-user
roleRef:
  kind: Role
  name: dev-role
  apiGroup: rbac.authorization.k8s.io
EOF
```

Create `config` and `credentials` files and set the environment variables
for `awscli`:

```shell
cat > "tmp/${CLUSTER_FQDN}/aws_config" << EOF
[profile dev]
role_arn=${MYUSER1_ROLE_ARN}
source_profile=eksDev
EOF

cat > "tmp/${CLUSTER_FQDN}/aws_credentials" << EOF
[eksDev]
aws_access_key_id=${MYUSER1_USER_ACCESSKEYMYUSER}
aws_secret_access_key=${MYUSER1_USER_SECRETACCESSKEY}
EOF
```

Extract `kubeconfig` and make it usable for dev profile:

```shell
if [[ ! -f "tmp/${CLUSTER_FQDN}/kubeconfig-dev-${CLUSTER_NAME}.conf" ]]; then
  eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig="tmp/${CLUSTER_FQDN}/kubeconfig-dev-${CLUSTER_NAME}.conf"
  cat >> "tmp/${CLUSTER_FQDN}/kubeconfig-dev-${CLUSTER_NAME}.conf" << EOF
      - name: AWS_PROFILE
        value: dev
      - name: AWS_CONFIG_FILE
        value: ${PWD}/tmp/${CLUSTER_FQDN}/aws_config
      - name: AWS_SHARED_CREDENTIALS_FILE
        value: ${PWD}/tmp/${CLUSTER_FQDN}/aws_credentials
EOF
fi
```

Output:

```text
2021-06-23 23:17:10 [ℹ]  eksctl version 0.54.0
2021-06-23 23:17:10 [ℹ]  using region eu-west-1
2021-06-23 23:17:10 [✔]  saved kubeconfig as "tmp/kube1.k8s.mylabs.dev/kubeconfig-dev-kube1.conf"
```

Set the AWS variables and verify the identity:

```shell
(
export AWS_CONFIG_FILE="tmp/${CLUSTER_FQDN}/aws_config"
export AWS_SHARED_CREDENTIALS_FILE="tmp/${CLUSTER_FQDN}/aws_credentials"
aws sts get-caller-identity --profile=dev | jq
)
```

Output:

```json
{
    "UserId": "Axxxxxxxxxxxxxxxxxxxx7:botocore-session-1624478440",
    "Account": "7xxxxxxxxxxx7",
    "Arn": "arn:aws:sts::7xxxxxxxxxxx7:assumed-role/myuser1-kube1/botocore-session-1624478440"
}
```

```shell
(
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

kubectl get pods -n kube-system --kubeconfig="tmp/${CLUSTER_FQDN}/kubeconfig-dev-${CLUSTER_NAME}.conf" || true
kubectl get pods -n development --kubeconfig="tmp/${CLUSTER_FQDN}/kubeconfig-dev-${CLUSTER_NAME}.conf"
kubectl run curl-test --namespace development --kubeconfig="tmp/${CLUSTER_FQDN}/kubeconfig-dev-${CLUSTER_NAME}.conf" --image=radial/busyboxplus:curl --rm -it -- ping -c 5 -w 50 www.google.com
kubectl get pods -n development --kubeconfig="tmp/${CLUSTER_FQDN}/kubeconfig-dev-${CLUSTER_NAME}.conf"
)
```

Output:

```text
Error from server (Forbidden): pods is forbidden: User "dev-user" cannot list resource "pods" in API group "" in the namespace "kube-system"
No resources found in development namespace.
If you don't see a command prompt, try pressing enter.
64 bytes from 74.125.193.103: seq=2 ttl=104 time=1.424 ms
64 bytes from 74.125.193.103: seq=3 ttl=104 time=1.440 ms
64 bytes from 74.125.193.103: seq=4 ttl=104 time=1.424 ms

--- www.google.com ping statistics ---
5 packets transmitted, 5 packets received, 0% packet loss
round-trip min/avg/max = 1.424/1.442/1.462 ms
Session ended, resume using 'kubectl attach curl-test -c curl-test -i -t' command when the pod is running
pod "curl-test" deleted
NAME        READY   STATUS        RESTARTS   AGE
curl-test   0/1     Terminating   0          8s
```

The output above is showing, that `dev-user` represented by
`tmp/${CLUSTER_FQDN}/kubeconfig-dev-${CLUSTER_NAME}.conf` and
`tmp/${CLUSTER_FQDN}/{aws_config,aws_credentials}` can only access the
`development` namespace and not the `kube-system`.
