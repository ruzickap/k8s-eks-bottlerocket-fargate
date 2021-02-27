# Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg?sanitize=true
"Clean-up")

Set necessary variables:

```bash
export BASE_DOMAIN="k8s.mylabs.dev"
export CLUSTER_NAME="k2"
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export AWS_DEFAULT_REGION="eu-central-1"
export KUBECONFIG=${PWD}/kubeconfig-${CLUSTER_NAME}.conf
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
  FARGATE_POD_EXECUTION_ROLE_ARN=$(eksctl get iamidentitymapping --cluster=${CLUSTER_NAME} -o json | jq -r ".[] | select (.rolearn | contains(\"FargatePodExecutionRole\")) .rolearn")
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
2021-02-22 15:50:49 [ℹ]  eksctl version 0.38.0
2021-02-22 15:50:49 [ℹ]  using region eu-central-1
2021-02-22 15:50:49 [ℹ]  deleting EKS cluster "k1"
2021-02-22 15:50:49 [ℹ]  deleting Fargate profile "fp-fgtest"
2021-02-22 15:55:05 [ℹ]  deleted Fargate profile "fp-fgtest"
2021-02-22 15:55:05 [ℹ]  deleted 1 Fargate profile(s)
2021-02-22 15:55:06 [✔]  kubeconfig has been updated
2021-02-22 15:55:06 [ℹ]  cleaning up AWS load balancers created by Kubernetes objects of Kind Service or Ingress
2021-02-22 15:55:39 [ℹ]  3 sequential tasks: { delete nodegroup "ng01", 2 sequential sub-tasks: { 5 parallel sub-tasks: { 2 sequential sub-tasks: { delete IAM role for serviceaccount "cert-manager/cert-manager", delete serviceaccount "cert-manager/cert-manager" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "harbor/harbor", delete serviceaccount "harbor/harbor" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "kube-system/ebs-csi-controller", delete serviceaccount "kube-system/ebs-csi-controller" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "kube-system/aws-node", delete serviceaccount "kube-system/aws-node" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "external-dns/external-dns", delete serviceaccount "external-dns/external-dns" } }, delete IAM OIDC provider }, delete cluster control plane "k1" [async] }
2021-02-22 15:55:39 [ℹ]  will delete stack "eksctl-k1-nodegroup-ng01"
2021-02-22 15:55:39 [ℹ]  waiting for stack "eksctl-k1-nodegroup-ng01" to get deleted
2021-02-22 15:55:39 [ℹ]  waiting for CloudFormation stack "eksctl-k1-nodegroup-ng01"
2021-02-22 15:55:39 [!]  retryable error (Throttling: Rate exceeded
2021-02-22 15:55:59 [ℹ]  waiting for CloudFormation stack "eksctl-k1-nodegroup-ng01"
2021-02-22 16:02:10 [ℹ]  waiting for CloudFormation stack "eksctl-k1-nodegroup-ng01"
2021-02-22 16:02:10 [ℹ]  will delete stack "eksctl-k1-addon-iamserviceaccount-harbor-harbor"
2021-02-22 16:02:10 [ℹ]  waiting for stack "eksctl-k1-addon-iamserviceaccount-harbor-harbor" to get deleted
2021-02-22 16:02:10 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-harbor-harbor"
2021-02-22 16:02:10 [ℹ]  will delete stack "eksctl-k1-addon-iamserviceaccount-kube-system-aws-node"
2021-02-22 16:02:10 [ℹ]  waiting for stack "eksctl-k1-addon-iamserviceaccount-kube-system-aws-node" to get deleted
2021-02-22 16:02:10 [ℹ]  will delete stack "eksctl-k1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-02-22 16:02:10 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-kube-system-aws-node"
2021-02-22 16:02:10 [ℹ]  waiting for stack "eksctl-k1-addon-iamserviceaccount-cert-manager-cert-manager" to get deleted
2021-02-22 16:02:10 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-02-22 16:02:10 [ℹ]  will delete stack "eksctl-k1-addon-iamserviceaccount-external-dns-external-dns"
2021-02-22 16:02:10 [ℹ]  waiting for stack "eksctl-k1-addon-iamserviceaccount-external-dns-external-dns" to get deleted
2021-02-22 16:02:10 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-external-dns-external-dns"
2021-02-22 16:02:10 [ℹ]  will delete stack "eksctl-k1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-02-22 16:02:10 [ℹ]  waiting for stack "eksctl-k1-addon-iamserviceaccount-kube-system-ebs-csi-controller" to get deleted
2021-02-22 16:02:10 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-02-22 16:02:27 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-02-22 16:02:28 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-external-dns-external-dns"
2021-02-22 16:02:28 [ℹ]  deleted serviceaccount "cert-manager/cert-manager"
2021-02-22 16:02:28 [ℹ]  deleted serviceaccount "external-dns/external-dns"
2021-02-22 16:02:28 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-kube-system-aws-node"
2021-02-22 16:02:28 [ℹ]  deleted serviceaccount "kube-system/aws-node"
2021-02-22 16:02:28 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-02-22 16:02:28 [ℹ]  deleted serviceaccount "kube-system/ebs-csi-controller"
2021-02-22 16:02:30 [ℹ]  waiting for CloudFormation stack "eksctl-k1-addon-iamserviceaccount-harbor-harbor"
2021-02-22 16:02:30 [ℹ]  deleted serviceaccount "harbor/harbor"
2021-02-22 16:02:32 [ℹ]  will delete stack "eksctl-k1-cluster"
2021-02-22 16:02:32 [✔]  all cluster resources were deleted
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

Remove CloudWatch log groups:

```bash
for LOG_GROUP in $(aws logs describe-log-groups | jq -r ".logGroups[] | select(.logGroupName|test(\"/${CLUSTER_NAME}/|/${CLUSTER_FQDN}/\")) .logGroupName"); do
  echo "*** Delete log group: ${LOG_GROUP}"
  aws logs delete-log-group --log-group-name "${LOG_GROUP}"
done
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
rm demo-magic.sh "${KUBECONFIG}" README.sh "kubeconfig-${CLUSTER_NAME}.conf.eksctl.lock" &> /dev/null || true
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
