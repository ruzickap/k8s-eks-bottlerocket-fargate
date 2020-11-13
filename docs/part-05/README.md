# Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg?sanitize=true
"Clean-up")

Set necessary variables:

```bash
export BASE_DOMAIN="k8s.mylabs.dev"
export CLUSTER_NAME="k1"
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export KUBECONFIG=${PWD}/kubeconfig-${CLUSTER_NAME}.conf
```

Uninstall external-dns otherwise it will be recreating the DNS entries:

```bash
helm uninstall --kubeconfig="${KUBECONFIG}" -n external-dns external-dns
```

Remove Route 53 DNS configuration:

```bash
BASE_DOMAIN_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
RESOURCE_RECORD_SET=$(aws route53 list-resource-record-sets --output json --hosted-zone-id "${BASE_DOMAIN_ZONE_ID}" | jq -c ".ResourceRecordSets[] | select(.Name==\"${CLUSTER_FQDN}.\")")
aws route53 change-resource-record-sets \
  --hosted-zone-id "${BASE_DOMAIN_ZONE_ID}" \
  --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet":
          '"${RESOURCE_RECORD_SET}"'
        }]}' | jq

CLUSTER_FQDN_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${CLUSTER_FQDN}.\`].Id" --output text)
aws route53 list-resource-record-sets --hosted-zone-id "${CLUSTER_FQDN_ZONE_ID}" | jq -c '.ResourceRecordSets[] | select (.Type != "SOA" and .Type != "NS")' |
while read -r RESOURCERECORDSET; do
  aws route53 change-resource-record-sets \
    --hosted-zone-id "${CLUSTER_FQDN_ZONE_ID}" \
    --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet": '"${RESOURCERECORDSET}"' }]}' \
    --output text --query 'ChangeInfo.Id'
done

aws route53 delete-hosted-zone --id "${CLUSTER_FQDN_ZONE_ID}" | jq
```

Remove RDS CloudFormation:

```bash
aws --region eu-central-1 cloudformation delete-stack --stack-name "${CLUSTER_NAME}-rds"
aws --region eu-central-1 cloudformation delete-stack --stack-name "${CLUSTER_NAME}-efs"
```

Remove EKS cluster:

```bash
eksctl delete cluster --region eu-central-1 --name=${CLUSTER_NAME} --wait
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

Remove Volumes related to the cluster:

```bash
VOLUMES=$(aws ec2 describe-volumes --region eu-central-1 --filter Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned --query 'Volumes[].VolumeId' --output text)
for VOLUME in ${VOLUMES}; do
  echo "Removing: ${VOLUME}"
  aws ec2 delete-volume --region eu-central-1 --volume-id "${VOLUME}"
done
```

Remove Route 53 Policy from AWS:

```bash
ROUTE53_POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName==\`${CLUSTER_FQDN}-AmazonRoute53Domains\`].{ARN:Arn}" --output text)
aws iam delete-policy --policy-arn "${ROUTE53_POLICY_ARN}"
```

Cleanup + Remove Helm:

```bash
if [[ -d ~/Library/Caches/helm ]]; then rm -rf ~/Library/Caches/helm; fi
if [[ -d ~/Library/Preferences/helm ]]; then rm -rf ~/Library/Preferences/helm; fi
if [[ -d ~/.helm ]]; then rm -rf ~/.helm; fi
```

Remove `tmp` directory:

```bash
rm -rf tmp
```

Remove other files:

```bash
rm demo-magic.sh "${KUBECONFIG}" README.sh
```
