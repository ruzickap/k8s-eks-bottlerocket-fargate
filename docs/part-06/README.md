# Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg?sanitize=true
"Clean-up")

Set necessary variables:

```bash
export BASE_DOMAIN="k8s.mylabs.dev"
export CLUSTER_NAME="k1"
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export AWS_DEFAULT_REGION="eu-central-1"
export KUBECONFIG=${PWD}/kubeconfig-${CLUSTER_NAME}.conf
```

Uninstall external-dns otherwise it will be recreating the DNS entries:

```bash
[[ -f ${KUBECONFIG} ]] && helm status -n external-dns external-dns > /dev/null && helm uninstall --kubeconfig="${KUBECONFIG}" -n external-dns external-dns
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

Remove CloudFormation stacks [Route53, S3, RDS, EFS]
(IAM policies will be removed later - after EKS):

```bash
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53-iam-s3"
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-rds"
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-efs"
```

Remove CloudFormation created by ClusterAPI:

```shell
clusterawsadm bootstrap iam delete-cloudformation-stack
```

Remove EKS cluster:

```bash
if eksctl get cluster --name k1 2>/dev/null ; then
  eksctl delete cluster --name=${CLUSTER_NAME} --wait
fi
```

Output:

```text
[ℹ]  eksctl version 0.31.0
[ℹ]  using region eu-central-1
[ℹ]  deleting EKS cluster "k1"
[ℹ]  deleting Fargate profile "fp-default"
[ℹ]  deleted Fargate profile "fp-default"
[ℹ]  deleting Fargate profile "fp-fargate-workload"
[ℹ]  deleted Fargate profile "fp-fargate-workload"
[ℹ]  deleted 2 Fargate profile(s)
[✔]  kubeconfig has been updated
[ℹ]  cleaning up AWS load balancers created by Kubernetes objects of Kind Service or Ingress
[ℹ]  3 sequential tasks: { delete nodegroup "ng01", 2 sequential sub-tasks: { 3 parallel sub-tasks: { 2 sequential sub-tasks: { delete IAM role for serviceaccount "cert-manager/cert-manager", delete serviceaccount "cert-manager/cert-manager" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "external-dns/external-dns", delete serviceaccount "external-dns/external-dns" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "kube-system/aws-node", delete serviceaccount "kube-system/aws-node" } }, delete IAM OIDC provider }, delete cluster control plane "k1" }
[ℹ]  will delete stack "eksctl-k1-nodegroup-ng01"
[ℹ]  waiting for stack "eksctl-k1-nodegroup-ng01" to get deleted
[ℹ]  will delete stack "eksctl-k1-addon-iamserviceaccount-kube-system-aws-node"
[ℹ]  waiting for stack "eksctl-k1-addon-iamserviceaccount-kube-system-aws-node" to get deleted
[ℹ]  will delete stack "eksctl-k1-addon-iamserviceaccount-external-dns-external-dns"
[ℹ]  waiting for stack "eksctl-k1-addon-iamserviceaccount-external-dns-external-dns" to get deleted
[ℹ]  will delete stack "eksctl-k1-addon-iamserviceaccount-cert-manager-cert-manager"
[ℹ]  waiting for stack "eksctl-k1-addon-iamserviceaccount-cert-manager-cert-manager" to get deleted
[ℹ]  serviceaccount "external-dns/external-dns" was already deleted
[ℹ]  deleted serviceaccount "cert-manager/cert-manager"
[ℹ]  deleted serviceaccount "kube-system/aws-node"
[ℹ]  will delete stack "eksctl-k1-cluster"
[ℹ]  waiting for stack "eksctl-k1-cluster" to get deleted
[✔]  all cluster resources were deleted
```

Remove IAM Policies using CloudFormation template which were not removed before
(they were used by EKS cluster when trying to remove them for the first time):

```bash
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53-iam-s3"
```

Remove Volumes related to the cluster:

```bash
VOLUMES=$(aws ec2 describe-volumes --filter Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned --query 'Volumes[].VolumeId' --output text) && \
for VOLUME in ${VOLUMES}; do
  echo "Removing: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
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

Remove `tmp` directory:

```bash
rm -rf tmp &> /dev/null
```

Remove other files:

```bash
rm demo-magic.sh "${KUBECONFIG}" README.sh &> /dev/null
```

Cleanup completed:

```bash
echo "Clenup completed..."
```
