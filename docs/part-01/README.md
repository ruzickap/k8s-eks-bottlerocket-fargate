# Amazon EKS Bottlerocket and Fargate

![Amazon EKS](https://raw.githubusercontent.com/cncf/landscape/7f5b02ecba914a32912e77fc78e1c54d1c2f98ec/hosted_logos/amazon-eks.svg?sanitize=true
"Amazon EKS")

Before starting with the main content, it's necessary to provision
the [Amazon EKS](https://aws.amazon.com/eks/) in AWS.

## Requirements

If you would like to follow this documents and it's task you will need to set up
few environment variables.

The `LETSENCRYPT_ENVIRONMENT` variable should be one of:

* `staging` - Let’s Encrypt will create testing certificate (not valid)
* `production` - Let’s Encrypt will create valid certificate (use with care)

`BASE_DOMAIN` contains DNS records for all your Kubernetes clusters. The cluster
names will look like `CLUSTER_NAME`.`BASE_DOMAIN` (`kube1.k8s.mylabs.dev`).

```bash
# Hostname / FQDN definitions
export BASE_DOMAIN=${BASE_DOMAIN:-k8s.mylabs.dev}
export CLUSTER_NAME=${CLUSTER_NAME:-kube1}
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export KUBECONFIG=${PWD}/kubeconfig-${CLUSTER_NAME}.conf
# * "production" - valid certificates signed by Lets Encrypt ""
# * "staging" - not trusted certs signed by Lets Encrypt "Fake LE Intermediate X1"
export LETSENCRYPT_ENVIRONMENT="staging"
export LETSENCRYPT_CERTIFICATE="https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem"
# export LETSENCRYPT_ENVIRONMENT="production"
# export LETSENCRYPT_CERTIFICATE="https://letsencrypt.org/certs/lets-encrypt-r3.pem"
export MY_EMAIL="petr.ruzicka@gmail.com"
# GitHub Organization + Team where are the users who will have the admin access
# to K8s resources (Grafana). Only users in GitHub organization
# (MY_GITHUB_ORG_NAME) will be able to access the apps via ingress.
export MY_GITHUB_ORG_NAME="ruzickap-org"
export MY_GITHUB_USERNAME="ruzickap"
# AWS Region
export AWS_DEFAULT_REGION="eu-central-1"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export AWS_ACCOUNT_ID
export SLACK_CHANNEL="mylabs"
# Tags used to tag the AWS resources
export TAGS="Owner=${MY_EMAIL} Environment=Dev Tribe=Cloud_Native Squad=Cloud_Container_Platform"
echo -e "${MY_EMAIL} | ${LETSENCRYPT_ENVIRONMENT} | ${CLUSTER_NAME} | ${BASE_DOMAIN} | ${CLUSTER_FQDN}\n${TAGS}"
```

Prepare GitHub OAuth "access" credentials ans AWS "access" variables.

You will need to configure AWS CLI: [https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)

```shell
# Common password
export MY_PASSWORD="xxxx"
# AWS Credentials
export AWS_ACCESS_KEY_ID="AxxxxxxxxxxxxxxxxxxY"
export AWS_SECRET_ACCESS_KEY="txxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxh"
# GitHub Organization OAuth Apps credentials
declare -A MY_GITHUB_ORG_OAUTH_CLIENT_ID MY_GITHUB_ORG_OAUTH_CLIENT_SECRET
MY_GITHUB_ORG_OAUTH_CLIENT_ID[${CLUSTER_NAME}]="3xxxxxxxxxxxxxxxxxx3"
MY_GITHUB_ORG_OAUTH_CLIENT_SECRET[${CLUSTER_NAME}]="7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx8"
export MY_GITHUB_ORG_OAUTH_CLIENT_ID MY_GITHUB_ORG_OAUTH_CLIENT_SECRET
# Sysdig credentials
export SYSDIG_AGENT_ACCESSKEY="xxx"
# Aqua credentials
export AQUA_REGISTRY_USERNAME="xxx"
export AQUA_REGISTRY_PASSWORD="xxx"
export AQUA_ENFORCER_TOKEN="xxx"
# Splunk credentials
export SPLUNK_HOST="xxx"
export SPLUNK_TOKEN="xxx"
export SPLUNK_INDEX_NAME="xxx"
# Slack incoming webhook
export SLACK_INCOMING_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
export SLACK_BOT_API_TOKEN="xxxx-xxxxxxxxxxxxx-xxxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxP"
```

## Prepare the local working environment

::: tip
You can skip these steps if you have all the required software already
installed.
:::

Install necessary software:

```bash
if [[ -x /usr/bin/apt-get ]]; then
  apt update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2-utils ansible awscli dnsutils git gnupg2 jq sudo unzip uuid > /dev/null
fi
```

Install [kubectl](https://github.com/kubernetes/kubectl) binary:

```bash
if [[ ! -x /usr/local/bin/kubectl ]]; then
  # https://github.com/kubernetes/kubectl/releases
  sudo curl -s -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/v1.20.5/bin/$(uname | sed "s/./\L&/g" )/amd64/kubectl"
  sudo chmod a+x /usr/local/bin/kubectl
fi
```

Install [Helm](https://helm.sh/):

```bash
if [[ ! -x /usr/local/bin/helm ]]; then
  # https://github.com/helm/helm/releases
  curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash -s -- --version v3.5.3
fi
```

Install [eksctl](https://eksctl.io/):

```bash
if [[ ! -x /usr/local/bin/eksctl ]]; then
  # https://github.com/weaveworks/eksctl/releases
  curl -s -L "https://github.com/weaveworks/eksctl/releases/download/0.46.0/eksctl_$(uname)_amd64.tar.gz" | sudo tar xz -C /usr/local/bin/
fi
```

Install [AWS IAM Authenticator for Kubernetes](https://github.com/kubernetes-sigs/aws-iam-authenticator):

```bash
if [[ ! -x /usr/local/bin/aws-iam-authenticator ]]; then
  # https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
  sudo curl -s -Lo /usr/local/bin/aws-iam-authenticator "https://amazon-eks.s3.us-west-2.amazonaws.com/1.19.6/2021-01-05/bin/$(uname | sed "s/./\L&/g")/amd64/aws-iam-authenticator"
  sudo chmod a+x /usr/local/bin/aws-iam-authenticator
fi
```

Install [vault](https://www.vaultproject.io/downloads):

```bash
if [[ ! -x /usr/local/bin/vault ]]; then
  curl -s -L "https://releases.hashicorp.com/vault/1.7.0/vault_1.7.0_$(uname | sed "s/./\L&/g")_amd64.zip" -o /tmp/vault.zip
  sudo unzip -q /tmp/vault.zip -d /usr/local/bin/
  rm /tmp/vault.zip
fi
```

Install [velero](https://github.com/vmware-tanzu/velero/releases):

```bash
if [[ ! -x /usr/local/bin/velero ]]; then
  curl -s -L "https://github.com/vmware-tanzu/velero/releases/download/v1.5.3/velero-v1.5.3-$(uname | sed "s/./\L&/g")-amd64.tar.gz" | sudo tar xz -C /usr/local/bin/ --strip-components 1 "velero-v1.5.3-$(uname | sed "s/./\L&/g")-amd64/velero"
fi
```

Install [flux](https://toolkit.fluxcd.io/):

```bash
if [[ ! -x /usr/local/bin/flux ]]; then
  curl -s https://toolkit.fluxcd.io/install.sh | sudo bash
fi
```

Install [calicoctl](https://docs.projectcalico.org/getting-started/clis/calicoctl/install):

```bash
if [[ ! -x /usr/local/bin/calicoctl ]]; then
  sudo curl -s -Lo /usr/local/bin/calicoctl https://github.com/projectcalico/calicoctl/releases/download/v3.18.1/calicoctl
  sudo chmod a+x /usr/local/bin/calicoctl
fi
```

Install [SOPS: Secrets OPerationS](https://github.com/mozilla/sops):

```bash
if [[ ! -x /usr/local/bin/sops ]]; then
  sudo curl -s -Lo /usr/local/bin/sops "https://github.com/mozilla/sops/releases/download/v3.7.0/sops-v3.7.0.$(uname | sed "s/./\L&/g")"
  sudo chmod a+x /usr/local/bin/sops
fi
```

Install [kustomize](https://kustomize.io/):

```bash
if [[ ! -x /usr/local/bin/kustomize ]]; then
  curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | sudo bash -s 4.0.5 /usr/local/bin/
fi
```

Install [hey](https://github.com/rakyll/hey):

```bash
if [[ ! -x /usr/local/bin/hey ]]; then
  sudo curl -s -Lo /usr/local/bin/hey "https://hey-release.s3.us-east-2.amazonaws.com/hey_$(uname | sed "s/./\L&/g")_amd64"
  sudo chmod a+x /usr/local/bin/hey
fi
```

## Configure AWS Route 53 Domain delegation

Create DNS zone (`BASE_DOMAIN`):

```shell
aws route53 create-hosted-zone --output json \
  --name "${BASE_DOMAIN}" \
  --caller-reference "$(date)" \
  --hosted-zone-config="{\"Comment\": \"Created by ${MY_EMAIL}\", \"PrivateZone\": false}" | jq
```

Use your domain registrar to change the nameservers for your zone (for example
"mylabs.dev") to use the Amazon Route 53 nameservers. Here is the way how you
can find out the the Route 53 nameservers:

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Create the NS record in `k8s.mylabs.dev` (`BASE_DOMAIN`) for proper zone
delegation. This step depends on your domain registrar - I'm using CloudFlare
and using Ansible to automate it:

```shell
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS1} solo=true proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS2} solo=false proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
```

Output:

```text
localhost | CHANGED => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": true,
    "result": {
        "record": {
            "content": "ns-885.awsdns-46.net",
            "created_on": "2020-11-13T06:25:32.18642Z",
            "id": "dxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxb",
            "locked": false,
            "meta": {
                "auto_added": false,
                "managed_by_apps": false,
                "managed_by_argo_tunnel": false,
                "source": "primary"
            },
            "modified_on": "2020-11-13T06:25:32.18642Z",
            "name": "k8s.mylabs.dev",
            "proxiable": false,
            "proxied": false,
            "ttl": 1,
            "type": "NS",
            "zone_id": "2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe",
            "zone_name": "mylabs.dev"
        }
    }
}
localhost | CHANGED => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": true,
    "result": {
        "record": {
            "content": "ns-1692.awsdns-19.co.uk",
            "created_on": "2020-11-13T06:25:37.605605Z",
            "id": "9xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxb",
            "locked": false,
            "meta": {
                "auto_added": false,
                "managed_by_apps": false,
                "managed_by_argo_tunnel": false,
                "source": "primary"
            },
            "modified_on": "2020-11-13T06:25:37.605605Z",
            "name": "k8s.mylabs.dev",
            "proxiable": false,
            "proxied": false,
            "ttl": 1,
            "type": "NS",
            "zone_id": "2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe",
            "zone_name": "mylabs.dev"
        }
    }
}
```

## Add new domain to Route 53, Policies, S3, EBS

Details with examples are described on these links:

* [https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/](https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/)
* [https://cert-manager.io/docs/configuration/acme/dns01/route53/](https://cert-manager.io/docs/configuration/acme/dns01/route53/)
* [https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)

Create CloudFormation template containing policies for Route53, S3 access
(Harbor, Velero) and Domain. Put new domain `CLUSTER_FQDN` to the Route 53 and
configure the DNS delegation from the `BASE_DOMAIN`.

```bash
mkdir -vp "tmp/${CLUSTER_FQDN}"

cat > "tmp/${CLUSTER_FQDN}/aws_policies.yml" << \EOF
Description: "Template to generate the necessary IAM Policies for access to Route53 and S3"
Parameters:
  ClusterFQDN:
    Description: "Cluster domain where all necessary app subdomains will live (subdomain of BaseDomain). Ex: kube1.k8s.mylabs.dev"
    Type: String
  ClusterName:
    Description: "Cluster Name Ex: kube1"
    Type: String
  BaseDomain:
    Description: "Base domain where cluster domains + their subdomains will live. Ex: k8s.mylabs.dev"
    Type: String
Resources:
  CloudWatchPolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${ClusterFQDN}-CloudWatch"
      Description: !Sub "Policy required by Fargate to log to CloudWatch for ${ClusterFQDN}"
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: Allow
          Action:
          - logs:CreateLogStream
          - logs:CreateLogGroup
          - logs:DescribeLogStreams
          - logs:PutLogEvents
          Resource: "*"
  HostedZone:
    Type: AWS::Route53::HostedZone
    Properties:
      Name: !Ref ClusterFQDN
  EKSKMSAlias:
    Type: AWS::KMS::Alias
    Properties:
      AliasName: !Sub "alias/eks-${ClusterName}"
      TargetKeyId: !Ref EKSKMSKey
  EKSKMSKey:
    Type: AWS::KMS::Key
    Properties:
      Description: !Sub "KMS key for EKS secrets encryption on ${ClusterFQDN}"
      EnableKeyRotation: true
      PendingWindowInDays: 7
      KeyPolicy:
        Version: "2012-10-17"
        Id: !Sub "eks-key-policy-${ClusterName}"
        Statement:
        - Sid: Enable IAM User Permissions
          Effect: Allow
          Principal:
            AWS: !Sub "arn:aws:iam::${AWS::AccountId}:root"
          Action: kms:*
          Resource: "*"
        - Sid: Allow use of the key
          Effect: Allow
          Principal:
            AWS:
            - !Sub arn:aws:iam::${AWS::AccountId}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling
          Action:
          - kms:Encrypt
          - kms:Decrypt
          - kms:ReEncrypt*
          - kms:GenerateDataKey*
          - kms:DescribeKey
          Resource: "*"
        - Sid: Allow attachment of persistent resources
          Effect: Allow
          Principal:
            AWS:
            - !Sub arn:aws:iam::${AWS::AccountId}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling
          Action:
          - kms:CreateGrant
          Resource: "*"
          Condition:
            Bool:
              kms:GrantIsForAWSResource: true
  RecordSet:
    Type: AWS::Route53::RecordSet
    Properties:
      HostedZoneName: !Sub "${BaseDomain}."
      Name: !Ref ClusterFQDN
      Type: NS
      TTL: 60
      ResourceRecords: !GetAtt HostedZone.NameServers
  S3Policy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${ClusterFQDN}-AmazonS3"
      Description: !Sub "Policy required by Harbor and Velero to write to S3 bucket ${ClusterFQDN}"
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: Allow
          Action:
          - s3:ListBucket
          - s3:GetBucketLocation
          - s3:ListBucketMultipartUploads
          Resource: !GetAtt S3Bucket.Arn
        - Effect: Allow
          Action:
          - s3:PutObject
          - s3:GetObject
          - s3:DeleteObject
          - s3:ListMultipartUploadParts
          - s3:AbortMultipartUpload
          Resource: !Sub "arn:aws:s3:::${ClusterFQDN}/*"
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      AccessControl: Private
      BucketName: !Sub "${ClusterFQDN}"
  VaultSecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Description: "Vault Root/Recovery key"
      KmsKeyId: !Ref VaultKMSKey
      SecretString: "empty"
  VaultKMSAlias:
    Type: AWS::KMS::Alias
    Properties:
      AliasName: !Sub "alias/eks-vault-${ClusterName}"
      TargetKeyId: !Ref VaultKMSKey
  VaultKMSKey:
    Type: AWS::KMS::Key
    Properties:
      Description: "Vault Seal/Unseal key"
      EnableKeyRotation: true
      PendingWindowInDays: 7
      KeyPolicy:
        Version: "2012-10-17"
        Id: vault-key-policy
        Statement:
          - Sid: Enable IAM User Permissions
            Effect: Allow
            Principal:
              AWS: !Sub "arn:aws:iam::${AWS::AccountId}:root"
            Action: kms:*
            Resource: "*"
Outputs:
  CloudWatchPolicyArn:
    Description: The ARN of the created CloudWatchPolicy
    Value: !Ref CloudWatchPolicy
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-CloudWatchPolicyArn"
  EKSKMSKeyArn:
    Description: The ARN of the created KMS Key to encrypt EKS related services
    Value: !GetAtt EKSKMSKey.Arn
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-EKSKMSKeyArn"
  EKSKMSKeyId:
    Description: The ID of the created KMS Key to encrypt EKS related services
    Value: !Ref EKSKMSKey
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-EKSKMSKeyId"
  HostedZoneArn:
    Description: The ARN of the created Route53 Zone for K8s cluster
    Value: !Ref HostedZone
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-HostedZoneArn"
  S3PolicyArn:
    Description: The ARN of the created AmazonS3 policy
    Value: !Ref S3Policy
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-S3PolicyArn"
  VaultKMSKeyId:
    Description: The AWS KMS Key ID used to Auto Unseal HashiCorp Vault and encrypt the ROOT TOKEN and Recovery Secret.
    Value: !Ref VaultKMSKey
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-VaultKMSKeyId"
EOF

eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterFQDN=${CLUSTER_FQDN} ClusterName=${CLUSTER_NAME} BaseDomain=${BASE_DOMAIN}" \
  --stack-name "${CLUSTER_NAME}-route53-iam-s3-ebs" --template-file "tmp/${CLUSTER_FQDN}/aws_policies.yml" --tags "${TAGS}"

AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-iam-s3-ebs")
CLOUDWATCH_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"CloudWatchPolicyArn\") .OutputValue")
EKS_KMS_KEY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"EKSKMSKeyArn\") .OutputValue")
EKS_KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"EKSKMSKeyId\") .OutputValue")
S3_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"S3PolicyArn\") .OutputValue")
VAULT_KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"VaultKMSKeyId\") .OutputValue")
```

Change TTL=60 of SOA + NS records for new domain
(it can not be done in CloudFormation):

```bash
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${CLUSTER_FQDN}.\`].Id" --output text)
RESOURCE_RECORD_SET_SOA=$(aws route53 --output json list-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --query "(ResourceRecordSets[?Type == \`SOA\`])[0]" | sed "s/\"TTL\":.*/\"TTL\": 60,/")
RESOURCE_RECORD_SET_NS=$(aws route53 --output json list-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --query "(ResourceRecordSets[?Type == \`NS\`])[0]" | sed "s/\"TTL\":.*/\"TTL\": 60,/")
cat << EOF | aws route53 --output json change-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --change-batch=file:///dev/stdin
{
    "Comment": "Update record to reflect new TTL for SOA and NS records",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet":
${RESOURCE_RECORD_SET_SOA}
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet":
${RESOURCE_RECORD_SET_NS}
        }
    ]
}
EOF
```

## Create Amazon EKS

![EKS](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/3-service-animated.gif
"EKS")

Create [Amazon EKS](https://aws.amazon.com/eks/) in AWS by using [eksctl](https://eksctl.io/).
It's a tool from [Weaveworks](https://weave.works/) based on official
AWS CloudFormation templates which will be used to launch and configure our
EKS cluster and nodes.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/c365149fc1a0b8d357139cbd6cda5aee8841c16c/logo/eksctl.png
"eksctl")

Generate SSH key if not exists:

```bash
test -f ~/.ssh/id_rsa.pub || ( install -m 0700 -d ~/.ssh && ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N "" )
```

Create the Amazon EKS cluster with Calico using `eksctl`:

```bash
cat > "tmp/${CLUSTER_FQDN}/eksctl.yaml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  # https://docs.aws.amazon.com/eks/latest/userguide/platform-versions.html
  version: "1.19"
  tags: &tags
$(echo "${TAGS}" | sed "s/ /\\n    /g; s/^/    /g; s/=/: /g")
availabilityZones:
  - ${AWS_DEFAULT_REGION}a
  - ${AWS_DEFAULT_REGION}b
iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: aws-load-balancer-controller
        namespace: kube-system
      wellKnownPolicies:
        awsLoadBalancerController: true
    - metadata:
        name: cert-manager
        namespace: cert-manager
      wellKnownPolicies:
        certManager: true
    - metadata:
        name: cluster-autoscaler
        namespace: kube-system
      wellKnownPolicies:
        autoScaler: true
    - metadata:
        name: external-dns
        namespace: external-dns
      wellKnownPolicies:
        externalDNS: true
    - metadata:
        name: ebs-csi-controller
        namespace: kube-system
      wellKnownPolicies:
        ebsCSIController: true
    - metadata:
        name: harbor
        namespace: harbor
      attachPolicyARNs:
        - ${S3_POLICY_ARN}
    - metadata:
        name: velero
        namespace: velero
      attachPolicyARNs:
        - ${S3_POLICY_ARN}
    - metadata:
        name: grafana
        namespace: kube-prometheus-stack
      attachPolicy:
        Version: 2012-10-17
        Statement:
        - Sid: AllowReadingMetricsFromCloudWatch
          Effect: Allow
          Action:
          - cloudwatch:DescribeAlarmsForMetric
          - cloudwatch:DescribeAlarmHistory
          - cloudwatch:DescribeAlarms
          - cloudwatch:ListMetrics
          - cloudwatch:GetMetricStatistics
          - cloudwatch:GetMetricData
          Resource: "*"
        - Sid: AllowReadingLogsFromCloudWatch
          Effect: Allow
          Action:
          - logs:DescribeLogGroups
          - logs:GetLogGroupFields
          - logs:StartQuery
          - logs:StopQuery
          - logs:GetQueryResults
          - logs:GetLogEvents
          Resource: "*"
        - Sid: AllowReadingTagsInstancesRegionsFromEC2
          Effect: Allow
          Action:
          - ec2:DescribeTags
          - ec2:DescribeInstances
          - ec2:DescribeRegions
          Resource: "*"
        - Sid: AllowReadingResourcesForTags
          Effect: Allow
          Action: tag:GetResources
          Resource: "*"
    # https://aws.amazon.com/blogs/containers/introducing-efs-csi-dynamic-provisioning/
    - metadata:
        name: efs-csi-controller-sa
        namespace: kube-system
      attachPolicy:
        Version: 2012-10-17
        Statement:
        - Effect: Allow
          Action:
          - elasticfilesystem:DescribeAccessPoints
          - elasticfilesystem:DescribeFileSystems
          Resource: "*"
        - Effect: Allow
          Action:
          - elasticfilesystem:CreateAccessPoint
          Resource: "*"
          Condition:
            StringLike:
              aws:RequestTag/efs.csi.aws.com/cluster: true
        - Effect: Allow
          Action: elasticfilesystem:DeleteAccessPoint
          Resource: "*"
          Condition:
            StringEquals:
              aws:ResourceTag/efs.csi.aws.com/cluster: true
vpc:
  nat:
    gateway: Disable
managedNodeGroups:
  - name: managed-ng-1
    # amiFamily: Bottlerocket
    instanceType: t3.xlarge
    instancePrefix: ruzickap
    desiredCapacity: 3
    minSize: 2
    maxSize: 4
    volumeSize: 30
    ssh:
      # Enable ssh access (via the admin container)
      allow: false
      publicKeyPath: ~/.ssh/id_rsa.pub
    labels:
      role: worker
    tags: *tags
    iam:
      withAddonPolicies:
        autoScaler: true
        # cloudWatch: true
        ebs: true
        efs: true
    # aws ec2 describe-images --owners amazon --filters "Name=name,Values=bottlerocket-aws-k8s-1.19*x86_64*" --region eu-central-1 --query "sort_by(Images, &CreationDate)"
    # aws ec2 describe-images --owners amazon --filters "Name=name,Values=amazon-eks-node-1.19*" --region eu-central-1 --query "sort_by(Images, &CreationDate)"
    # ami: ami-079b6e99f49a1cd7b
    maxPodsPerNode: 1000
    volumeEncrypted: true
    volumeKmsKeyID: ${EKS_KMS_KEY_ID}
    # bottlerocket:
    #   enableAdminContainer: true
fargateProfiles:
  - name: fp-fgtest
    selectors:
      - namespace: fgtest
    tags: *tags
secretsEncryption:
  keyARN: ${EKS_KMS_KEY_ARN}
# cloudWatch:
#   clusterLogging:
#     enableTypes: ["audit", "authenticator", "controllerManager"]
EOF

eksctl create cluster --config-file "tmp/${CLUSTER_FQDN}/eksctl.yaml" --kubeconfig "${KUBECONFIG}" --without-nodegroup
kubectl delete daemonset -n kube-system aws-node
kubectl apply -f https://docs.projectcalico.org/manifests/calico-vxlan.yaml
eksctl create nodegroup --config-file "tmp/${CLUSTER_FQDN}/eksctl.yaml"
```

Output:

```text
2021-03-27 12:26:44 [ℹ]  eksctl version 0.41.0
2021-03-27 12:26:44 [ℹ]  using region eu-central-1
2021-03-27 12:26:44 [ℹ]  subnets for eu-central-1a - public:192.168.0.0/19 private:192.168.64.0/19
2021-03-27 12:26:44 [ℹ]  subnets for eu-central-1b - public:192.168.32.0/19 private:192.168.96.0/19
2021-03-27 12:26:44 [ℹ]  using Kubernetes version 1.19
2021-03-27 12:26:44 [ℹ]  creating EKS cluster "kube1" in "eu-central-1" region with Fargate profile
2021-03-27 12:26:44 [ℹ]  will create a CloudFormation stack for cluster itself and 0 nodegroup stack(s)
2021-03-27 12:26:44 [ℹ]  will create a CloudFormation stack for cluster itself and 0 managed nodegroup stack(s)
2021-03-27 12:26:44 [ℹ]  if you encounter any issues, check CloudFormation console or try 'eksctl utils describe-stacks --region=eu-central-1 --cluster=kube1'
2021-03-27 12:26:44 [ℹ]  Kubernetes API endpoint access will use default of {publicAccess=true, privateAccess=false} for cluster "kube1" in "eu-central-1"
2021-03-27 12:26:44 [ℹ]  2 sequential tasks: { create cluster control plane "kube1", 2 sequential sub-tasks: { 7 sequential sub-tasks: { wait for control plane to become ready, tag cluster, update CloudWatch logging configuration, create fargate profiles, associate IAM OIDC provider, 7 parallel sub-tasks: { 2 sequential sub-tasks: { create IAM role for serviceaccount "kube-system/aws-load-balancer-controller", create serviceaccount "kube-system/aws-load-balancer-controller" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "cert-manager/cert-manager", create serviceaccount "cert-manager/cert-manager" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "kube-system/cluster-autoscaler", create serviceaccount "kube-system/cluster-autoscaler" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "external-dns/external-dns", create serviceaccount "external-dns/external-dns" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "kube-system/ebs-csi-controller", create serviceaccount "kube-system/ebs-csi-controller" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "harbor/harbor", create serviceaccount "harbor/harbor" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "kube-system/aws-node", create serviceaccount "kube-system/aws-node" } }, restart daemonset "kube-system/aws-node" }, create addons } }
2021-03-27 12:26:44 [ℹ]  building cluster stack "eksctl-kube1-cluster"
2021-03-27 12:26:50 [ℹ]  deploying stack "eksctl-kube1-cluster"
2021-03-27 12:27:20 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-cluster"
2021-03-27 12:37:07 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-cluster"
2021-03-27 12:37:08 [✔]  tagged EKS cluster (Environment=Dev, Owner=petr.ruzicka@gmail.com, Squad=Cloud_Container_Platform, Tribe=Cloud_Native)
2021-03-27 12:37:10 [ℹ]  waiting for requested "LoggingUpdate" in cluster "kube1" to succeed
2021-03-27 12:37:26 [ℹ]  waiting for requested "LoggingUpdate" in cluster "kube1" to succeed
2021-03-27 12:37:43 [ℹ]  waiting for requested "LoggingUpdate" in cluster "kube1" to succeed
2021-03-27 12:38:03 [ℹ]  waiting for requested "LoggingUpdate" in cluster "kube1" to succeed
2021-03-27 12:38:03 [✔]  configured CloudWatch logging for cluster "kube1" in "eu-central-1" (enabled types: audit, authenticator, controllerManager & disabled types: api, scheduler)
2021-03-27 12:38:03 [ℹ]  creating Fargate profile "fp-fgtest" on EKS cluster "kube1"
2021-03-27 12:40:13 [ℹ]  created Fargate profile "fp-fgtest" on EKS cluster "kube1"
2021-03-27 12:40:16 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-03-27 12:40:16 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-03-27 12:40:16 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-03-27 12:40:16 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-03-27 12:40:16 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-03-27 12:40:16 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-03-27 12:40:16 [ℹ]  building iamserviceaccount stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-03-27 12:40:16 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-03-27 12:40:16 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-03-27 12:40:16 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-03-27 12:40:16 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-03-27 12:40:16 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-03-27 12:40:16 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-03-27 12:40:16 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-03-27 12:40:16 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-03-27 12:40:16 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-03-27 12:40:16 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-03-27 12:40:16 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-03-27 12:40:16 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-03-27 12:40:16 [ℹ]  deploying stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-03-27 12:40:16 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-03-27 12:40:33 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-03-27 12:40:33 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-03-27 12:40:33 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-03-27 12:40:34 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-03-27 12:40:35 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-03-27 12:40:35 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-03-27 12:40:35 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-03-27 12:40:50 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-03-27 12:40:50 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-cluster-autoscaler"
2021-03-27 12:40:51 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-harbor-harbor"
2021-03-27 12:40:52 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
2021-03-27 12:40:53 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2021-03-27 12:40:53 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-kube-system-ebs-csi-controller"
2021-03-27 12:40:54 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
2021-03-27 12:40:55 [ℹ]  created namespace "harbor"
2021-03-27 12:40:55 [ℹ]  created namespace "cert-manager"
2021-03-27 12:40:55 [ℹ]  created serviceaccount "harbor/harbor"
2021-03-27 12:40:55 [ℹ]  serviceaccount "kube-system/aws-node" already exists
2021-03-27 12:40:55 [ℹ]  created serviceaccount "kube-system/aws-load-balancer-controller"
2021-03-27 12:40:55 [ℹ]  created serviceaccount "cert-manager/cert-manager"
2021-03-27 12:40:55 [ℹ]  created serviceaccount "kube-system/ebs-csi-controller"
2021-03-27 12:40:55 [ℹ]  created serviceaccount "kube-system/cluster-autoscaler"
2021-03-27 12:40:55 [ℹ]  updated serviceaccount "kube-system/aws-node"
2021-03-27 12:41:13 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
2021-03-27 12:41:13 [ℹ]  created namespace "external-dns"
2021-03-27 12:41:13 [ℹ]  created serviceaccount "external-dns/external-dns"
2021-03-27 12:41:13 [ℹ]  daemonset "kube-system/aws-node" restarted
2021-03-27 12:41:13 [ℹ]  waiting for the control plane availability...
2021-03-27 12:41:13 [✔]  saved kubeconfig as "/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/kubeconfig-kube1.conf"
2021-03-27 12:41:13 [ℹ]  no tasks
2021-03-27 12:41:13 [✔]  all EKS cluster resources for "kube1" have been created
2021-03-27 12:41:14 [ℹ]  kubectl command should work with "/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/kubeconfig-kube1.conf", try 'kubectl --kubeconfig=/Users/ruzickap/git/k8s-eks-bottlerocket-fargate/kubeconfig-kube1.conf get nodes'
2021-03-27 12:41:14 [✔]  EKS cluster "kube1" in "eu-central-1" region is ready
daemonset.apps "aws-node" deleted
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/bgppeers.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/blockaffinities.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/clusterinformations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/felixconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworksets.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/hostendpoints.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamblocks.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamconfigs.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamhandles.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ippools.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/kubecontrollersconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networksets.crd.projectcalico.org created
clusterrole.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrolebinding.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrole.rbac.authorization.k8s.io/calico-node created
clusterrolebinding.rbac.authorization.k8s.io/calico-node created
daemonset.apps/calico-node created
serviceaccount/calico-node created
deployment.apps/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
poddisruptionbudget.policy/calico-kube-controllers created
2021-03-27 12:41:28 [ℹ]  eksctl version 0.41.0
2021-03-27 12:41:28 [ℹ]  using region eu-central-1
2021-03-27 12:41:40 [ℹ]  using SSH public key "/Users/ruzickap/.ssh/id_rsa.pub" as "eksctl-kube1-nodegroup-managed-ng-1-a3:84:e4:0d:af:5f:c8:40:da:71:68:8a:74:c7:ba:16"
2021-03-27 12:41:50 [ℹ]  1 nodegroup (managed-ng-1) was included (based on the include/exclude rules)
2021-03-27 12:41:50 [ℹ]  will create a CloudFormation stack for each of 1 managed nodegroups in cluster "kube1"
2021-03-27 12:41:51 [ℹ]  2 sequential tasks: { fix cluster compatibility, 1 task: { 1 task: { create managed nodegroup "managed-ng-1" } } }
2021-03-27 12:41:51 [ℹ]  checking cluster stack for missing resources
2021-03-27 12:41:52 [ℹ]  cluster stack has all required resources
2021-03-27 12:41:52 [ℹ]  building managed nodegroup stack "eksctl-kube1-nodegroup-managed-ng-1"
2021-03-27 12:41:52 [ℹ]  deploying stack "eksctl-kube1-nodegroup-managed-ng-1"
2021-03-27 12:45:15 [ℹ]  waiting for CloudFormation stack "eksctl-kube1-nodegroup-managed-ng-1"
2021-03-27 12:45:21 [ℹ]  no tasks
2021-03-27 12:45:21 [✔]  created 0 nodegroup(s) in cluster "kube1"
2021-03-27 12:45:21 [ℹ]  nodegroup "managed-ng-1" has 3 node(s)
2021-03-27 12:45:21 [ℹ]  node "ip-192-168-35-254.eu-central-1.compute.internal" is ready
2021-03-27 12:45:21 [ℹ]  node "ip-192-168-42-218.eu-central-1.compute.internal" is ready
2021-03-27 12:45:21 [ℹ]  node "ip-192-168-5-152.eu-central-1.compute.internal" is ready
2021-03-27 12:45:21 [ℹ]  waiting for at least 2 node(s) to become ready in "managed-ng-1"
2021-03-27 12:45:21 [ℹ]  nodegroup "managed-ng-1" has 3 node(s)
2021-03-27 12:45:21 [ℹ]  node "ip-192-168-35-254.eu-central-1.compute.internal" is ready
2021-03-27 12:45:21 [ℹ]  node "ip-192-168-42-218.eu-central-1.compute.internal" is ready
2021-03-27 12:45:21 [ℹ]  node "ip-192-168-5-152.eu-central-1.compute.internal" is ready
2021-03-27 12:45:21 [✔]  created 1 managed nodegroup(s) in cluster "kube1"
2021-03-27 12:45:22 [ℹ]  checking security group configuration for all nodegroups
2021-03-27 12:45:22 [ℹ]  all nodegroups have up-to-date configuration
```

When the cluster is ready it immediately start pushing logs to CloudWatch under
`/aws/eks/kube1/cluster`.

Check the nodes+pods and max number of nodes which can be scheduled on one node:

```bash
kubectl get nodes,pods -o wide --all-namespaces
```

Output:

```text
NAME                                                   STATUS   ROLES    AGE   VERSION              INTERNAL-IP      EXTERNAL-IP      OS-IMAGE         KERNEL-VERSION               CONTAINER-RUNTIME
node/ip-192-168-35-254.eu-central-1.compute.internal   Ready    <none>   90s   v1.19.6-eks-49a6c0   192.168.35.254   18.197.27.232    Amazon Linux 2   5.4.95-42.163.amzn2.x86_64   docker://19.3.13
node/ip-192-168-42-218.eu-central-1.compute.internal   Ready    <none>   83s   v1.19.6-eks-49a6c0   192.168.42.218   3.124.218.81     Amazon Linux 2   5.4.95-42.163.amzn2.x86_64   docker://19.3.13
node/ip-192-168-5-152.eu-central-1.compute.internal    Ready    <none>   81s   v1.19.6-eks-49a6c0   192.168.5.152    18.184.216.224   Amazon Linux 2   5.4.95-42.163.amzn2.x86_64   docker://19.3.13

NAMESPACE     NAME                                           READY   STATUS    RESTARTS   AGE     IP               NODE                                              NOMINATED NODE   READINESS GATES
kube-system   pod/calico-kube-controllers-69496d8b75-7dxxx   1/1     Running   0          3m53s   172.16.20.194    ip-192-168-35-254.eu-central-1.compute.internal   <none>           <none>
kube-system   pod/calico-node-gfdb8                          1/1     Running   0          90s     192.168.35.254   ip-192-168-35-254.eu-central-1.compute.internal   <none>           <none>
kube-system   pod/calico-node-p9bpp                          1/1     Running   0          83s     192.168.42.218   ip-192-168-42-218.eu-central-1.compute.internal   <none>           <none>
kube-system   pod/calico-node-shnf8                          1/1     Running   0          81s     192.168.5.152    ip-192-168-5-152.eu-central-1.compute.internal    <none>           <none>
kube-system   pod/coredns-7cfc675d7d-7px4j                   1/1     Running   0          11m     172.16.20.193    ip-192-168-35-254.eu-central-1.compute.internal   <none>           <none>
kube-system   pod/coredns-7cfc675d7d-rhz6l                   1/1     Running   0          11m     172.16.20.195    ip-192-168-35-254.eu-central-1.compute.internal   <none>           <none>
kube-system   pod/kube-proxy-gbxg9                           1/1     Running   0          81s     192.168.5.152    ip-192-168-5-152.eu-central-1.compute.internal    <none>           <none>
kube-system   pod/kube-proxy-pdspj                           1/1     Running   0          83s     192.168.42.218   ip-192-168-42-218.eu-central-1.compute.internal   <none>           <none>
kube-system   pod/kube-proxy-zlqxp                           1/1     Running   0          90s     192.168.35.254   ip-192-168-35-254.eu-central-1.compute.internal   <none>           <none>
```
