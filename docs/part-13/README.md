# Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg?sanitize=true
"Clean-up")

Set necessary variables:

```bash
export BASE_DOMAIN=${BASE_DOMAIN:-k8s.mylabs.dev}
export CLUSTER_NAME=${CLUSTER_NAME:-kube1}
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export AWS_DEFAULT_REGION="eu-central-1"
export KUBECONFIG=${PWD}/kubeconfig-${CLUSTER_NAME}.conf
export MY_GITHUB_USERNAME="ruzickap"
```

Remove CloudFormation stacks [RDS, EFS]:

```bash
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-rds"
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-efs"
```

Delete IstioOperator to release AWS Load Balancer:

```bash
kubectl delete istiooperator -n istio-system istio-controlplane || true
```

Detach policy from IAM role:

```bash
if AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-iam-s3-ebs"); then
  CLOUDWATCH_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"CloudWatchPolicyArn\") .OutputValue")
  FARGATE_POD_EXECUTION_ROLE_ARN=$(eksctl get iamidentitymapping --cluster="${CLUSTER_NAME}" -o json | jq -r ".[] | select (.rolearn | contains(\"FargatePodExecutionRole\")) .rolearn")
  aws iam detach-role-policy --policy-arn "${CLOUDWATCH_POLICY_ARN}" --role-name "${FARGATE_POD_EXECUTION_ROLE_ARN#*/}" || true
fi
```

Remove EKS cluster:

```bash
if eksctl get cluster --name=${CLUSTER_NAME} 2>/dev/null ; then
  eksctl delete cluster --name=${CLUSTER_NAME}
fi
```

Output:

```text
021-03-20 10:43:18 [ℹ]  eksctl version 0.41.0
2021-03-20 10:43:18 [ℹ]  using region eu-central-1
NAME  VERSION STATUS  CREATED      VPC      SUBNETS                         SECURITYGROUPS
kube1 1.19  ACTIVE  2021-03-20T08:49:00Z  vpc-04b281d5fd7e9bd0b subnet-04da0f0a9da6485e2,subnet-0cc009de72130b4c3,subnet-0d52dc1b7ede44311,subnet-0f7d6d9f948a65fcd sg-065b5eac812787d11
2021-03-20 10:43:19 [ℹ]  eksctl version 0.41.0
2021-03-20 10:43:19 [ℹ]  using region eu-central-1
2021-03-20 10:43:19 [ℹ]  deleting EKS cluster "kube1"
2021-03-20 10:43:20 [ℹ]  deleting Fargate profile "fp-fgtest"
2021-03-20 10:47:36 [ℹ]  deleted Fargate profile "fp-fgtest"
2021-03-20 10:47:36 [ℹ]  deleted 1 Fargate profile(s)
2021-03-20 10:47:37 [✔]  kubeconfig has been updated
2021-03-20 10:47:37 [ℹ]  cleaning up AWS load balancers created by Kubernetes objects of Kind Service or Ingress
2021-03-20 10:48:09 [ℹ]  3 sequential tasks: { delete nodegroup "managed-ng-1", 2 sequential sub-tasks: { 7 parallel sub-tasks: { 2 sequential sub-tasks: { delete IAM role for serviceaccount "external-dns/external-dns", delete serviceaccount "external-dns/external-dns" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "cert-manager/cert-manager", delete serviceaccount "cert-manager/cert-manager" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "kube-system/aws-load-balancer-controller", delete serviceaccount "kube-system/aws-load-balancer-controller" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "kube-system/ebs-csi-controller", delete serviceaccount "kube-system/ebs-csi-controller" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "harbor/harbor", delete serviceaccount "harbor/harbor" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "kube-system/cluster-autoscaler", delete serviceaccount "kube-system/cluster-autoscaler" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "kube-system/aws-node", delete serviceaccount "kube-system/aws-node" } }, delete IAM OIDC provider }, delete cluster control plane "kube1" [async] }
2021-03-20 10:48:10 [ℹ]  will delete stack "eksctl-kube1-nodegroup-managed-ng-1"
2021-03-20 10:48:10 [ℹ]  waiting for stack "eksctl-kube1-nodegroup-managed-ng-1" to get deleted
2021-03-20 10:48:10 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-nodegroup-managed-ng-1"
...
2021-03-20 11:00:23 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-nodegroup-managed-ng-1"
2021-03-20 11:00:23 [ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-03-20 11:00:23 [ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node" to get deleted
2021-03-20 11:00:23 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-03-20 11:00:23 [ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-03-20 11:00:23 [ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor" to get deleted
2021-03-20 11:00:23 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-03-20 11:00:23 [ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-03-20 11:00:23 [ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler" to get deleted
2021-03-20 11:00:23 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-03-20 11:00:23 [ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-03-20 11:00:23 [ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller" to get deleted
2021-03-20 11:00:23 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-03-20 11:00:23 [ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-03-20 11:00:23 [ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns" to get deleted
2021-03-20 11:00:23 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-03-20 11:00:23 [ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-03-20 11:00:23 [ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller" to get deleted
2021-03-20 11:00:23 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-03-20 11:00:23 [ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-03-20 11:00:23 [ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager" to get deleted
2021-03-20 11:00:23 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-03-20 11:00:41 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-03-20 11:00:41 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-03-20 11:00:41 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-03-20 11:00:41 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
```

Remove Route 53 DNS records from DNS Zone:

```bash
CLUSTER_FQDN_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${CLUSTER_FQDN}.\`].Id" --output text)
if [[ -n "${CLUSTER_FQDN_ZONE_ID}" ]]; then
  aws route53 list-resource-record-sets --hosted-zone-id "${CLUSTER_FQDN_ZONE_ID}" | jq -c '.ResourceRecordSets[] | select (.Type != "SOA" and .Type != "NS")' |
  while read -r RESOURCERECORDSET; do
    aws route53 change-resource-record-sets \
      --hosted-zone-id "${CLUSTER_FQDN_ZONE_ID}" \
      --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet": '"${RESOURCERECORDSET}"' }]}' \
      --output text --query 'ChangeInfo.Id'
  done
fi
```

Remove all S3 data form the bucket:

```bash
if aws s3api head-bucket --bucket "${CLUSTER_FQDN}" 2>/dev/null; then
  aws s3 rm s3://${CLUSTER_FQDN}/ --recursive
fi
```

Output:

```text
delete: s3://kube1.k8s.mylabs.dev/harbor/docker/registry/v2/blobs/sha256/0f/0f2d0c63fe0b32e5cb326248d96ee59799b6e55c9257f72c556b14a4dced0881/data
delete: s3://kube1.k8s.mylabs.dev/harbor/docker/registry/v2/blobs/sha256/02/026a6f0bbb704596202b0d24ad1fc1d0d7349cc72e4c89b6438a7aec82b1523c/data
delete: s3://kube1.k8s.mylabs.dev/harbor/docker/registry/v2/blobs/sha256/00/000eee12ec04cc914bf96e8f5dee7767510c2aca3816af6078bd9fbe3150920c/data
delete: s3://kube1.k8s.mylabs.dev/harbor/docker/registry/v2/blobs/sha256/15/156d91b88c44fcb49ebd386f213854774ce523a33ff4fab5dac2c403cc6ebeee/data
delete: s3://kube1.k8s.mylabs.dev/harbor/docker/registry/v2/blobs/sha256/16/162a4534982f0e8b2432dfd48098f0bc74d1aefb23198981a7fb22de243fd8bf/data
...
delete: s3://kube1.k8s.mylabs.dev/velero/backups/backup-vault/backup-vault-logs.gz
delete: s3://kube1.k8s.mylabs.dev/velero/backups/backup-vault/backup-vault-csi-volumesnapshots.json.gz
delete: s3://kube1.k8s.mylabs.dev/velero/backups/backup-vault/backup-vault-podvolumebackups.json.gz
delete: s3://kube1.k8s.mylabs.dev/velero/backups/backup-vault/backup-vault-resource-list.json.gz
delete: s3://kube1.k8s.mylabs.dev/velero/backups/backup-vault/backup-vault-volumesnapshots.json.gz
delete: s3://kube1.k8s.mylabs.dev/velero/restores/restore-vault/restore-restore-vault-logs.gz
delete: s3://kube1.k8s.mylabs.dev/velero/backups/backup-vault/backup-vault.tar.gz
...
```

Remove CloudFormation stacks [Route53+IAM+S3+EBS]

```bash
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53-iam-s3-ebs"
```

Remove CloudFormation created by ClusterAPI:

```shell
clusterawsadm bootstrap iam delete-cloudformation-stack
```

Remove Volumes and Snapshots related to the cluster:

```bash
VOLUMES=$(aws ec2 describe-volumes --filter Name=tag:kubernetes.io/cluster/${CLUSTER_FQDN},Values=owned --query 'Volumes[].VolumeId' --output text) && \
for VOLUME in ${VOLUMES}; do
  echo "Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done

SNAPSHOTS=$(aws ec2 describe-snapshots --filter Name=tag:kubernetes.io/cluster/${CLUSTER_FQDN},Values=owned --query 'Snapshots[].SnapshotId' --output text) && \
for SNAPSHOT in ${SNAPSHOTS}; do
  echo "Removing Snapshot: ${SNAPSHOT}"
  aws ec2 delete-snapshot --snapshot-id "${SNAPSHOT}"
done
```

Output:

```text
Removing Volume: vol-0e14bc9ea5aecf058
Removing Volume: vol-007e121915a9eb8d8
Removing Volume: vol-0d1a1a3c740d5a269
Removing Volume: vol-0436ca80dc2f2b20a
Removing Snapshot: snap-041cb25d72d64b161
```

Remove CloudWatch log groups:

```bash
for LOG_GROUP in $(aws logs describe-log-groups | jq -r ".logGroups[] | select(.logGroupName|test(\"/${CLUSTER_NAME}/|/${CLUSTER_FQDN}/\")) .logGroupName"); do
  echo "*** Delete log group: ${LOG_GROUP}"
  aws logs delete-log-group --log-group-name "${LOG_GROUP}"
done
```

Remove GitHub repository created for Flux:

```bash
curl -H "Authorization: token $GITHUB_TOKEN" -X DELETE "https://api.github.com/repos/${MY_GITHUB_USERNAME}/${CLUSTER_NAME}-k8s-clusters"
```

Stop gpg-agent:

```bash
GNUPGHOME="${PWD}/tmp/${CLUSTER_FQDN}/.gnupg" gpgconf --kill gpg-agent
```

Remove Helm data:

```bash
if [[ -d ~/Library/Caches/helm ]]; then rm -rf ~/Library/Caches/helm; fi
if [[ -d ~/Library/Preferences/helm ]]; then rm -rf ~/Library/Preferences/helm; fi
if [[ -d ~/.helm ]]; then rm -rf ~/.helm; fi
```

Remove `tmp/${CLUSTER_FQDN}` directory:

```bash
rm -rf "tmp/${CLUSTER_FQDN}" &> /dev/null
```

Remove other files:

```bash
rm /tmp/demo-magic.sh "${KUBECONFIG}" /tmp/README-${CLUSTER_NAME}.sh "kubeconfig-${CLUSTER_NAME}.conf.eksctl.lock" &> /dev/null || true
```

Wait for CloudFormation to be deleted:

```bash
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-route53-iam-s3-ebs"
aws cloudformation wait stack-delete-complete --stack-name "eksctl-${CLUSTER_NAME}-cluster"
```

Cleanup completed:

```bash
echo "Cleanup completed..."
```
