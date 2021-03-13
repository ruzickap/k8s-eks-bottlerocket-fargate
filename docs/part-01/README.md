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
names will look like `CLUSTER_NAME`.`BASE_DOMAIN` (`k1.k8s.mylabs.dev`).

```bash
# Hostname / FQDN definitions
export BASE_DOMAIN="k8s.mylabs.dev"
export CLUSTER_NAME="k1"
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export KUBECONFIG=${PWD}/kubeconfig-${CLUSTER_NAME}.conf
# * "production" - valid certificates signed by Lets Encrypt ""
# * "staging" - not trusted certs signed by Lets Encrypt "Fake LE Intermediate X1"
export LETSENCRYPT_ENVIRONMENT=${LETSENCRYPT_ENVIRONMENT:-staging}
export LETSENCRYPT_CERTIFICATE="https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem"
# export LETSENCRYPT_ENVIRONMENT=${LETSENCRYPT_ENVIRONMENT:-production}
# export LETSENCRYPT_CERTIFICATE="https://letsencrypt.org/certs/lets-encrypt-r3.pem"
export MY_EMAIL="petr.ruzicka@gmail.com"
# GitHub Organization + Team where are the users who will have the admin access
# to K8s resources (Grafana). Only users in GitHub organization
# (MY_GITHUB_ORG_NAME) will be able to access the apps via ingress.
export MY_GITHUB_ORG_NAME="ruzickap-org"
# AWS Region
export AWS_DEFAULT_REGION="eu-central-1"
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
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2-utils ansible awscli dnsutils git jq sudo unzip > /dev/null
fi
```

Install [kubectl](https://github.com/kubernetes/kubectl) binary:

```bash
if [[ ! -x /usr/local/bin/kubectl ]]; then
  # https://github.com/kubernetes/kubectl/releases
  sudo curl -s -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/v1.19.5/bin/$(uname | sed "s/./\L&/g" )/amd64/kubectl"
  sudo chmod a+x /usr/local/bin/kubectl
fi
```

Install [Helm](https://helm.sh/):

```bash
if [[ ! -x /usr/local/bin/helm ]]; then
  # https://github.com/helm/helm/releases
  curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash -s -- --version v3.5.0
fi
```

Install [eksctl](https://eksctl.io/):

```bash
if [[ ! -x /usr/local/bin/eksctl ]]; then
  # https://github.com/weaveworks/eksctl/releases
  curl -s -L "https://github.com/weaveworks/eksctl/releases/download/0.38.0/eksctl_$(uname)_amd64.tar.gz" | sudo tar xz -C /usr/local/bin/
fi
```

Install [AWS IAM Authenticator for Kubernetes](https://github.com/kubernetes-sigs/aws-iam-authenticator):

```bash
if [[ ! -x /usr/local/bin/aws-iam-authenticator ]]; then
  # https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
  sudo curl -s -Lo /usr/local/bin/aws-iam-authenticator "https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/$(uname | sed "s/./\L&/g")/amd64/aws-iam-authenticator"
  sudo chmod a+x /usr/local/bin/aws-iam-authenticator
fi
```

Install [vault](https://www.vaultproject.io/downloads):

```bash
if [[ ! -x /usr/local/bin/vault ]]; then
  curl -s -L "https://releases.hashicorp.com/vault/1.6.1/vault_1.6.1_$(uname | sed "s/./\L&/g")_amd64.zip" -o /tmp/vault.zip
  unzip -q /tmp/vault.zip -d /usr/local/bin/
  rm /tmp/vault.zip
fi
```

Install [velero](https://github.com/vmware-tanzu/velero/releases):

```bash
if [[ ! -x /usr/local/bin/velero ]]; then
  curl -s -L "https://github.com/vmware-tanzu/velero/releases/download/v1.5.3/velero-v1.5.3-$(uname | sed "s/./\L&/g")-amd64.tar.gz" | sudo tar xz -C /usr/local/bin/ --strip-components 1 "velero-v1.5.3-$(uname | sed "s/./\L&/g")-amd64/velero"
fi
```

## Configure AWS Route 53 Domain delegation

Create DNS zone (`BASE_DOMAIN`):

```shell
aws route53 create-hosted-zone --output json \
  --name ${BASE_DOMAIN} \
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
(Harbor) and Domain. AWS IAM Policy `${ClusterFQDN}-AmazonRoute53Domains`
allows `cert-manager` and `external-dns` to modify the Route 53 entries.
Put new domain `CLUSTER_FQDN` to the Route 53 and configure the
DNS delegation from the `BASE_DOMAIN`.

```bash
test -d "tmp/${CLUSTER_FQDN}" || mkdir -vp "tmp/${CLUSTER_FQDN}"

cat > "tmp/${CLUSTER_FQDN}/aws_policies.yml" << \EOF
Description: "Template to generate the necessary IAM Policies for access to Route53 and S3"
Parameters:
  ClusterFQDN:
    Description: "Cluster domain where all necessary app subdomains will live (subdomain of BaseDomain). Ex: k1.k8s.mylabs.dev"
    Type: String
  ClusterName:
    Description: "Cluster Name Ex: k1"
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
EKS_KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"EKSKMSKeyId\") .OutputValue")
EKS_KMS_KEY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"EKSKMSKeyArn\") .OutputValue")
S3_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"S3PolicyArn\") .OutputValue")
VAULT_KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"VaultKMSKeyId\") .OutputValue")
CLOUDWATCH_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"CloudWatchPolicyArn\") .OutputValue")
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
test -f ~/.ssh/id_rsa || ( install -m 0700 -d ~/.ssh && ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N "" )
```

Create the Amazon EKS cluster using `eksctl`:

```bash
eksctl create cluster --config-file - --kubeconfig "${KUBECONFIG}" << EOF
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
      attachPolicy:
        Version: "2012-10-17"
        Statement:
        - Effect: Allow
          Action:
          - ec2:AttachVolume
          - ec2:CreateSnapshot
          - ec2:CreateTags
          - ec2:CreateVolume
          - ec2:DeleteSnapshot
          - ec2:DeleteTags
          - ec2:DeleteVolume
          - ec2:DescribeAvailabilityZones
          - ec2:DescribeInstances
          - ec2:DescribeSnapshots
          - ec2:DescribeTags
          - ec2:DescribeVolumes
          - ec2:DescribeVolumesModifications
          - ec2:DetachVolume
          - ec2:ModifyVolume
          Resource: "*"
    - metadata:
        name: harbor
        namespace: harbor
      attachPolicyARNs:
        - ${S3_POLICY_ARN}
vpc:
  nat:
    gateway: Disable
nodeGroups:
  - name: ng01
    # amiFamily: Bottlerocket
    instanceType: t3.xlarge
    instancePrefix: ruzickap
    desiredCapacity: 3
    minSize: 2
    maxSize: 4
    volumeSize: 20
    ssh:
      # Enable ssh access (via the admin container)
      allow: true
      publicKeyPath: ~/.ssh/id_rsa.pub
    labels:
      role: worker
    tags: *tags
    iam:
      # Required for sysdig-agent
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess
      withAddonPolicies:
        autoScaler: true
        cloudWatch: true
        ebs: true
        efs: true
    # aws ec2 describe-images --owners amazon --filters "Name=name,Values=bottlerocket-aws-k8s-1.18*x86_64*" --region eu-central-1 --query "sort_by(Images, &CreationDate)"
    # aws ec2 describe-images --owners amazon --filters "Name=name,Values=amazon-eks-node-1.18*" --region eu-central-1 --query "sort_by(Images, &CreationDate)"
    ami: ami-028e864a893e18733
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
cloudWatch:
  clusterLogging:
    enableTypes: ["audit", "authenticator", "controllerManager"]
EOF
```

Output:

```text
```

When the cluster is ready it immediately start pushing logs to CloudWatch under
`/aws/eks/k1/cluster`.

Check the nodes:

```bash
kubectl get nodes -o wide
```

Output:

```text
NAME                                             STATUS   ROLES    AGE   VERSION    INTERNAL-IP     EXTERNAL-IP     OS-IMAGE                KERNEL-VERSION   CONTAINER-RUNTIME
ip-192-168-3-46.eu-central-1.compute.internal    Ready    <none>   64s   v1.18.14   192.168.3.46    18.184.208.47   Bottlerocket OS 1.0.5   5.4.80           containerd://1.3.7+bottlerocket
ip-192-168-37-96.eu-central-1.compute.internal   Ready    <none>   65s   v1.18.14   192.168.37.96   3.127.247.51    Bottlerocket OS 1.0.5   5.4.80           containerd://1.3.7+bottlerocket
```

Attach the policy to the [pod execution role](https://docs.aws.amazon.com/eks/latest/userguide/pod-execution-role.html)
of your EKS on Fargate cluster:

```bash
FARGATE_POD_EXECUTION_ROLE_ARN=$(eksctl get iamidentitymapping --cluster=${CLUSTER_NAME} -o json | jq -r ".[] | select (.rolearn | contains(\"FargatePodExecutionRole\")) .rolearn")
aws iam attach-role-policy --policy-arn "${CLOUDWATCH_POLICY_ARN}" --role-name "${FARGATE_POD_EXECUTION_ROLE_ARN#*/}"
```

Create the dedicated `aws-observability` namespace and the ConfigMap for Fluent Bit:

```bash
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
