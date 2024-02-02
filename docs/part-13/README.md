# Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg?sanitize=true
"Clean-up")

Install necessary software:

```bash
if command -v apt-get &> /dev/null; then
  apt update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq less curl gnupg2 jq python3 sudo unzip > /dev/null
fi
```

Install [AWS CLI](https://aws.amazon.com/cli/) binary:

```bash
if ! command -v aws &> /dev/null; then
  curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
  unzip -q -o /tmp/awscliv2.zip -d /tmp/
  sudo /tmp/aws/install
fi
```

Install [kubectl](https://github.com/kubernetes/kubectl) binary:

```bash
if ! command -v kubectl &> /dev/null; then
  sudo curl -s -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/v1.21.1/bin/$(uname | sed "s/./\L&/g")/amd64/kubectl"
  sudo chmod a+x /usr/local/bin/kubectl
fi
```

Install [AWS IAM Authenticator for Kubernetes](https://github.com/kubernetes-sigs/aws-iam-authenticator):

```bash
if ! command -v aws-iam-authenticator &> /dev/null; then
  sudo curl -s -Lo /usr/local/bin/aws-iam-authenticator "https://amazon-eks.s3.us-west-2.amazonaws.com/1.19.6/2021-01-05/bin/$(uname | sed "s/./\L&/g")/amd64/aws-iam-authenticator"
  sudo chmod a+x /usr/local/bin/aws-iam-authenticator
fi
```

Install [eksctl](https://eksctl.io/):

```bash
if ! command -v eksctl &> /dev/null; then
  curl -s -L "https://github.com/weaveworks/eksctl/releases/download/0.60.0/eksctl_$(uname)_amd64.tar.gz" | sudo tar xz -C /usr/local/bin/
fi
```

Set necessary variables:

```bash
export BASE_DOMAIN=${BASE_DOMAIN:-k8s.mylabs.dev}
export CLUSTER_NAME=${CLUSTER_NAME:-kube1}
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export AWS_DEFAULT_REGION="eu-west-1"
export KUBECONFIG=${PWD}/kubeconfig-${CLUSTER_NAME}.conf
export MY_GITHUB_USERNAME="ruzickap"
```

Remove CloudFormation stacks [RDS, EFS]:

```bash
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-rds"
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-efs"
```

Delete all cluster created by Cluster API (if any):

```bash
kubectl delete Cluster,AWSManagedControlPlane,MachinePool,AWSManagedMachinePool,ClusterResourceSet -n tenants --all || true
```

Delete IstioOperator to release AWS Load Balancer:

```bash
kubectl delete istiooperator -n istio-system istio-controlplane || true
```

Detach policy from IAM role:

```bash
if AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-iam-s3-kms-asm"); then
  CLOUDWATCH_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"CloudWatchPolicyArn\") .OutputValue")
  FARGATE_POD_EXECUTION_ROLE_ARN=$(eksctl get iamidentitymapping --cluster="${CLUSTER_NAME}" -o json | jq -r ".[] | select (.rolearn | contains(\"FargatePodExecutionRole\")) .rolearn")
  aws iam detach-role-policy --policy-arn "${CLOUDWATCH_POLICY_ARN}" --role-name "${FARGATE_POD_EXECUTION_ROLE_ARN#*/}" || true
fi
```

Remove EKS cluster:

```bash
if eksctl get cluster --name="${CLUSTER_NAME}" 2> /dev/null; then
  eksctl delete cluster --name="${CLUSTER_NAME}"
fi
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
if aws s3api head-bucket --bucket "${CLUSTER_FQDN}" 2> /dev/null; then
  aws s3 rm "s3://${CLUSTER_FQDN}/" --recursive
fi
```

Remove APM:

```bash
if aws amp list-workspaces | grep -q "${CLUSTER_FQDN}"; then
  aws amp delete-workspace --workspace-id="$(aws amp list-workspaces --alias="${CLUSTER_FQDN}" | jq .workspaces[0].workspaceId -r)"
fi
```

Remove CloudFormation stacks [Route53+IAM+S3+EBS]

```bash
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53-iam-s3-kms-asm"
```

Remove CloudFormation created by ClusterAPI:

```bash
aws cloudformation delete-stack --stack-name "cluster-api-provider-aws-sigs-k8s-io"
```

Remove Volumes and Snapshots related to the cluster:

```bash
VOLUMES=$(aws ec2 describe-volumes --filter "Name=tag:Cluster,Values=${CLUSTER_FQDN}" --query 'Volumes[].VolumeId' --output text) &&
  for VOLUME in ${VOLUMES}; do
    echo "Removing Volume: ${VOLUME}"
    aws ec2 delete-volume --volume-id "${VOLUME}"
  done

SNAPSHOTS=$(aws ec2 describe-snapshots --filter "Name=tag:Cluster,Values=${CLUSTER_FQDN}" --query 'Snapshots[].SnapshotId' --output text) &&
  for SNAPSHOT in ${SNAPSHOTS}; do
    echo "Removing Snapshot: ${SNAPSHOT}"
    aws ec2 delete-snapshot --snapshot-id "${SNAPSHOT}"
  done
```

Remove orphan ELBs (if exists):

```bash
for ELB_ARN in $(aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerArn" --output=text); do
  if [[ -n "$(aws elbv2 describe-tags --resource-arns "${ELB_ARN}" --query "TagDescriptions[].Tags[?Key == \`kubernetes.io/cluster/${CLUSTER_NAME}\`]" --output text)" ]]; then
    echo "Deleting ELB: ${ELB_ARN}"
    aws elbv2 delete-load-balancer --load-balancer-arn "${ELB_ARN}"
  fi
done
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
rm /tmp/demo-magic.sh "${KUBECONFIG}" "/tmp/README-${CLUSTER_NAME}.sh" "kubeconfig-${CLUSTER_NAME}.conf.eksctl.lock" &> /dev/null || true
```

Wait for CloudFormation to be deleted:

```bash
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-route53-iam-s3-kms-asm"
aws cloudformation wait stack-delete-complete --stack-name "eksctl-${CLUSTER_NAME}-cluster"
```

Cleanup completed:

```bash
echo "Cleanup completed..."
```
