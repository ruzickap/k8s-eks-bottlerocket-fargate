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
# AWS Credentials
export AWS_ACCESS_KEY_ID="AxxxxxxxxxxxxxxxxxxY"
export AWS_SECRET_ACCESS_KEY="txxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxh"
# GitHub Organization OAuth Apps credentials
export MY_GITHUB_ORG_OAUTH_CLIENT_ID="3xxxxxxxxxxxxxxxxxx3"
export MY_GITHUB_ORG_OAUTH_CLIENT_SECRET="7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx8"
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
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible awscli git jq sudo
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
  curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash -s -- --version v3.4.0
fi
```

Install [eksctl](https://eksctl.io/):

```bash
if [[ ! -x /usr/local/bin/eksctl ]]; then
  # https://github.com/weaveworks/eksctl/releases
  curl -s -L "https://github.com/weaveworks/eksctl/releases/download/0.34.0/eksctl_$(uname)_amd64.tar.gz" | sudo tar xz -C /usr/local/bin/
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
  unzip /tmp/vault.zip -d /usr/local/bin/
  rm /tmp/vault.zip
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
test -d tmp || mkdir -v tmp

cat > tmp/aws_policies.yml << \EOF
Description: "Template to generate the necessary IAM Policies for access to Route53 and S3"
Parameters:
  ClusterFQDN:
    Description: "Cluster domain where all necessary app subdomains will live (subdomain of BaseDomain). Ex: k1.k8s.mylabs.dev"
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
  EBSPolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${ClusterFQDN}-AmazonEBS"
      Description: !Sub "Policy required by  Amazon EBS Container Storage Interface (CSI) Driver (aws-ebs-csi-driver) to manage EBS volumes on ${ClusterFQDN}"
      PolicyDocument:
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
  HostedZone:
    Type: AWS::Route53::HostedZone
    Properties:
      Name: !Ref ClusterFQDN
  RecordSet:
    Type: AWS::Route53::RecordSet
    Properties:
      HostedZoneName: !Sub "${BaseDomain}."
      Name: !Ref ClusterFQDN
      Type: NS
      TTL: 60
      ResourceRecords: !GetAtt HostedZone.NameServers
  Route53Policy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${ClusterFQDN}-AmazonRoute53Domains"
      Description: !Sub "Policy required by cert-manager or external-dns to be able to modify Route 53 entries for ${ClusterFQDN}"
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: Allow
          Action:
          - route53:GetChange
          Resource: "arn:aws:route53:::change/*"
        - Effect: Allow
          Action:
          - route53:ChangeResourceRecordSets
          - route53:ListResourceRecordSets
          Resource: !Sub "arn:aws:route53:::hostedzone/${HostedZone.Id}"
        - Effect: Allow
          Action:
          - route53:ListHostedZones
          - route53:ListHostedZonesByName
          Resource: "*"
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
      KmsKeyId: !Ref VaultKmsKey
      SecretString: "empty"
  VaultKmsAlias:
    Type: AWS::KMS::Alias
    Properties:
      AliasName: alias/Vault_key
      TargetKeyId: !Ref VaultKmsKey
  VaultKmsKey:
    Type: AWS::KMS::Key
    Properties:
      Description: "Vault Seal/Unseal key"
      PendingWindowInDays: 7
      KeyPolicy:
        Version: "2012-10-17"
        Id: key-default-1
        Statement:
        - Sid: Enable IAM User Permissions
          Effect: Allow
          Principal:
            AWS: !Sub "arn:aws:iam::${AWS::AccountId}:root"
          Action: kms:*
          Resource: "*"
Outputs:
  CloudWatchPolicy:
    Description: The ARN of the created CloudWatchPolicy
    Value:
      Ref: CloudWatchPolicy
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-CloudWatchPolicy"
  EBSPolicy:
    Description: The ARN of the created AmazonEBS policy
    Value:
      Ref: EBSPolicy
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-EBSPolicy"
  HostedZone:
    Description: The ARN of the created Route53 Zone for K8s cluster
    Value:
      Ref: HostedZone
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-HostedZone"
  Route53Policy:
    Description: The ARN of the created AmazonRoute53Domains policy
    Value:
      Ref: Route53Policy
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-Route53Policy"
  S3Policy:
    Description: The ARN of the created AmazonS3 policy
    Value:
      Ref: S3Policy
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-S3Policy"
  S3Bucket:
    Description: The ARN of the created S3 bucket for Harbor and Velero
    Value:
      Ref: S3Bucket
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-S3Bucket"
  VaultSecret:
    Value: !Ref "VaultSecret"
    Description: The AWS Secrets Manager Secret containing the ROOT TOKEN and Recovery Secret for HashiCorp Vault.
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-VaultSecret"
  VaultKMSKeyId:
    Value: !Ref "VaultKmsKey"
    Description: The AWS KMS Key used to Auto Unseal HashiCorp Vault and encrypt the ROOT TOKEN and Recovery Secret.
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-VaultKMSKeyId"
  VaultKMSKeyArn:
    Value: !GetAtt "VaultKmsKey.Arn"
    Description: The AWS KMS Key used to Auto Unseal HashiCorp Vault and encrypt the ROOT TOKEN and Recovery Secret.
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-VaultKMSKeyArn"
EOF

eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterFQDN=${CLUSTER_FQDN} BaseDomain=${BASE_DOMAIN}" \
  --stack-name "${CLUSTER_NAME}-route53-iam-s3-ebs" --template-file tmp/aws_policies.yml --tags "${TAGS}"

AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-iam-s3-ebs")
EBS_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"EBSPolicy\") .OutputValue")
ROUTE53_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"Route53Policy\") .OutputValue")
S3_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"S3Policy\") .OutputValue")
KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"VaultKMSKeyId\") .OutputValue")
CLOUDWATCH_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"CloudWatchPolicy\") .OutputValue")
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
# https://eksctl.io/usage/schema/
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "1.18"
  tags: &tags
    Owner: ${MY_EMAIL}
    Environment: Dev
    Tribe: Cloud_Native
    Squad: Cloud_Container_Platform

availabilityZones:
  - ${AWS_DEFAULT_REGION}a
  - ${AWS_DEFAULT_REGION}b

iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: ebs-csi-controller-sa
        namespace: kube-system
      attachPolicyARNs:
        - ${EBS_POLICY_ARN}
    - metadata:
        name: ebs-snapshot-controller
        namespace: kube-system
      attachPolicyARNs:
        - ${EBS_POLICY_ARN}
    - metadata:
        name: cert-manager
        namespace: cert-manager
      attachPolicyARNs:
        - ${ROUTE53_POLICY_ARN}
    - metadata:
        name: external-dns
        namespace: external-dns
      attachPolicyARNs:
        - ${ROUTE53_POLICY_ARN}
    - metadata:
        name: harbor
        namespace: harbor
      attachPolicyARNs:
        - ${S3_POLICY_ARN}
    # - metadata:
    #     name: velero-server
    #     namespace: velero
    #   attachPolicyARNs:
    #     - ${S3_POLICY_ARN}

nodeGroups:
  - name: ng01
    amiFamily: Bottlerocket
    instanceType: t3.large
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    volumeSize: 0
    ssh:
      # Enable ssh access (via the admin container)
      allow: true
      publicKeyPath: ~/.ssh/id_rsa.pub
    labels:
      role: worker
    tags: *tags
    iam:
      withAddonPolicies:
        autoScaler: true
        cloudWatch: true
        ebs: true
        efs: true
        xRay: true
    volumeType: gp2
    volumeEncrypted: true
    bottlerocket:
      enableAdminContainer: true
      settings:
        motd: "Hello, eksctl!"
fargateProfiles:
  - name: fp-fgtest
    selectors:
      - namespace: fgtest
    tags: *tags

cloudWatch:
  clusterLogging:
    enableTypes: ["audit", "authenticator", "controllerManager"]
EOF
```

Output:

```text
[ℹ]  eksctl version 0.34.0
[ℹ]  using region eu-central-1
[ℹ]  subnets for eu-central-1a - public:192.168.0.0/19 private:192.168.64.0/19
[ℹ]  subnets for eu-central-1b - public:192.168.32.0/19 private:192.168.96.0/19
[ℹ]  nodegroup "ng01" will use "ami-0770b08976be5e4aa" [AmazonLinux2/1.18]
[ℹ]  using SSH public key "/root/.ssh/id_rsa.pub" as "eksctl-k1-nodegroup-ng01-a3:84:e4:0d:af:5f:c8:40:da:71:68:8a:74:c7:ba:16"
[ℹ]  using Kubernetes version 1.18
[ℹ]  creating EKS cluster "k1" in "eu-central-1" region with Fargate profile and un-managed nodes
[ℹ]  1 nodegroup (ng01) was included (based on the include/exclude rules)
[ℹ]  will create a CloudFormation stack for cluster itself and 1 nodegroup stack(s)
[ℹ]  will create a CloudFormation stack for cluster itself and 0 managed nodegroup stack(s)
[ℹ]  if you encounter any issues, check CloudFormation console or try 'eksctl utils describe-stacks --region=eu-central-1 --cluster=k1'
[ℹ]  Kubernetes API endpoint access will use default of {publicAccess=true, privateAccess=false} for cluster "k1" in "eu-central-1"
[ℹ]  2 sequential tasks: { create cluster control plane "k1", 3 sequential sub-tasks: { 6 sequential sub-tasks: { tag cluster, update CloudWatch logging configuration, create fargate profiles, associate IAM OIDC provider, 5 parallel sub-tasks: { 2 sequential sub-tasks: { create IAM role for serviceaccount "cert-manager/cert-manager", create serviceaccount "cert-manager/cert-manager" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "external-dns/external-dns", create serviceaccount "external-dns/external-dns" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "harbor/harbor", create serviceaccount "harbor/harbor" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "velero/velero", create serviceaccount "velero/velero" }, 2 sequential sub-tasks: { create IAM role for serviceaccount "kube-system/aws-node", create serviceaccount "kube-system/aws-node" } }, restart daemonset "kube-system/aws-node" }, create addons, create nodegroup "ng01" } }
[ℹ]  building cluster stack "eksctl-k1-cluster"
[ℹ]  deploying stack "eksctl-k1-cluster"
[✔]  tagged EKS cluster (Environment=Dev, Owner=petr.ruzicka@gmail.com, Squad=Cloud_Container_Platform, Tribe=Cloud_Native)
[✔]  configured CloudWatch logging for cluster "k1" in "eu-central-1" (enabled types: audit, authenticator, controllerManager & disabled types: api, scheduler)
[ℹ]  creating Fargate profile "fp-default" on EKS cluster "k1"
[ℹ]  created Fargate profile "fp-default" on EKS cluster "k1"
[ℹ]  creating Fargate profile "fp-fargate-workload" on EKS cluster "k1"
[ℹ]  created Fargate profile "fp-fargate-workload" on EKS cluster "k1"
[ℹ]  building iamserviceaccount stack "eksctl-k1-addon-iamserviceaccount-external-dns-external-dns"
[ℹ]  building iamserviceaccount stack "eksctl-k1-addon-iamserviceaccount-cert-manager-cert-manager"
[ℹ]  building iamserviceaccount stack "eksctl-k1-addon-iamserviceaccount-kube-system-aws-node"
[ℹ]  building iamserviceaccount stack "eksctl-k1-addon-iamserviceaccount-harbor-harbor"
[ℹ]  building iamserviceaccount stack "eksctl-k1-addon-iamserviceaccount-velero-velero"
[ℹ]  deploying stack "eksctl-k1-addon-iamserviceaccount-kube-system-aws-node"
[ℹ]  deploying stack "eksctl-k1-addon-iamserviceaccount-external-dns-external-dns"
[ℹ]  deploying stack "eksctl-k1-addon-iamserviceaccount-cert-manager-cert-manager"
[ℹ]  deploying stack "eksctl-k1-addon-iamserviceaccount-velero-velero"
[ℹ]  deploying stack "eksctl-k1-addon-iamserviceaccount-harbor-harbor"
[ℹ]  created namespace "harbor"
[ℹ]  created serviceaccount "harbor/harbor"
[ℹ]  created namespace "velero"
[ℹ]  created serviceaccount "velero/velero"
[ℹ]  serviceaccount "kube-system/aws-node" already exists
[ℹ]  updated serviceaccount "kube-system/aws-node"
[ℹ]  created namespace "external-dns"
[ℹ]  created serviceaccount "external-dns/external-dns"
[ℹ]  created namespace "cert-manager"
[ℹ]  created serviceaccount "cert-manager/cert-manager"
[ℹ]  daemonset "kube-system/aws-node" restarted
[ℹ]  building nodegroup stack "eksctl-k1-nodegroup-ng01"
[ℹ]  deploying stack "eksctl-k1-nodegroup-ng01"
[ℹ]  waiting for the control plane availability...
[✔]  saved kubeconfig as "/mnt/kubeconfig-k1.conf"
[ℹ]  no tasks
[✔]  all EKS cluster resources for "k1" have been created
[ℹ]  adding identity "arn:aws:iam::729560437327:role/eksctl-k1-nodegroup-ng01-NodeInstanceRole-1KP39SOLWQ5T9" to auth ConfigMap
[ℹ]  nodegroup "ng01" has 0 node(s)
[ℹ]  waiting for at least 2 node(s) to become ready in "ng01"
[ℹ]  nodegroup "ng01" has 2 node(s)
[ℹ]  node "ip-192-168-46-39.eu-central-1.compute.internal" is ready
[ℹ]  node "ip-192-168-8-205.eu-central-1.compute.internal" is ready
[ℹ]  kubectl command should work with "/mnt/kubeconfig-k1.conf", try 'kubectl --kubeconfig=/mnt/kubeconfig-k1.conf get nodes'
[✔]  EKS cluster "k1" in "eu-central-1" region is ready
```

When the cluster is ready it immediately start pushing logs to CloudWatch under
`/aws/eks/k1/cluster`.

Remove namespaces with serviceaccounts created by `eksctl`:

```bash
kubectl delete serviceaccount -n cert-manager cert-manager
kubectl delete serviceaccount -n external-dns external-dns
kubectl delete serviceaccount -n kube-system ebs-csi-controller-sa
kubectl delete serviceaccount -n kube-system ebs-snapshot-controller
```

Check the nodes:

```bash
kubectl get nodes -o wide
```

Output:

```text
NAME                                             STATUS   ROLES    AGE     VERSION              INTERNAL-IP     EXTERNAL-IP      OS-IMAGE         KERNEL-VERSION                  CONTAINER-RUNTIME
ip-192-168-46-39.eu-central-1.compute.internal   Ready    <none>   2m13s   v1.18.9-eks-d1db3c   192.168.46.39   18.193.105.122   Amazon Linux 2   4.14.203-156.332.amzn2.x86_64   docker://19.3.6
ip-192-168-8-205.eu-central-1.compute.internal   Ready    <none>   2m7s    v1.18.9-eks-d1db3c   192.168.8.205   54.93.80.77      Amazon Linux 2   4.14.203-156.332.amzn2.x86_64   docker://19.3.6
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
