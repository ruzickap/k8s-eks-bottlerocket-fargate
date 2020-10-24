# Workload

Run some workload on the K8s...

## podinfo

Install `podinfo`:

```bash
helm repo add --force-update sp https://stefanprodan.github.io/podinfo ; helm repo update > /dev/null
helm install --version 5.0.2 --values - podinfo sp/podinfo << EOF
# https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  path: /
  hosts:
    - podinfo.${MY_DOMAIN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo.${MY_DOMAIN}
EOF
```

Output:

```text
"sp" has been added to your repositories
NAME: podinfo
LAST DEPLOYED: Sat Oct 24 16:50:26 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  https://podinfo.kube1.mylabs.dev/
```

Install `podinfo` secured by `oauth2`:

```bash
helm install --version 5.0.2 --values - podinfo-oauth sp/podinfo << EOF
# https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://auth.${MY_DOMAIN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://auth.${MY_DOMAIN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  path: /
  hosts:
    - podinfo-oauth.${MY_DOMAIN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo-oauth.${MY_DOMAIN}
EOF
```

## Drupal installation

Get details about AWS environment where is the EKS cluster and store it into
variables:

```bash
EKS_CLUSTER_NAME=$(echo ${MY_DOMAIN} | cut -f 1 -d .)
EKS_VPC_ID=$(aws eks --region eu-central-1 describe-cluster --name "${EKS_CLUSTER_NAME}" \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)
EKS_VPC_CIDR=$(aws ec2 --region eu-central-1 describe-vpcs --vpc-ids "${EKS_VPC_ID}" \
  --query "Vpcs[].CidrBlock" --output text)
EKS_PRIVATE_SUBNETS=$(aws ec2 --region eu-central-1 describe-subnets \
  --filter Name=tag:alpha.eksctl.io/cluster-name,Values=${EKS_CLUSTER_NAME} \
  | jq -r "[.Subnets[] | select(.MapPublicIpOnLaunch == false) .SubnetId] | join(\",\")")
EKS_PRIVATE_SUBNET1=$(echo $EKS_PRIVATE_SUBNETS | cut -d , -f 1)
EKS_PRIVATE_SUBNET2=$(echo $EKS_PRIVATE_SUBNETS | cut -d , -f 2)
RDS_DB_PASSWORD="123-My_Secret_Password-456"
TAGS="Owner=petr.ruzicka@gmail.com Environment=Dev Tribe=Cloud_Native Squad=Cloud_Container_Platform"
```

### RDS

Apply CloudFormation template to create Amazon RDS MariaDB database.
The template below is inspired by: [https://github.com/aquasecurity/marketplaces/blob/master/aws/cloudformation/AquaRDS.yaml](https://github.com/aquasecurity/marketplaces/blob/master/aws/cloudformation/AquaRDS.yaml)

```bash
cat > tmp/cf_rds.yml << EOF
AWSTemplateFormatVersion: 2010-09-09
Description: >-
  This AWS CloudFormation template installs the AWS RDS MariaDB database.
Metadata:
  "AWS::CloudFormation::Interface":
    ParameterLabels:
      VpcID:
        default: VPC ID that hosts the EKS and will host the RDS instance
      VpcIPCidr:
        default: VPC CIDR
      EksInstanceSubnets:
        default: Private Subnets from the EKS VPC
      RdsInstanceName:
        default: RDS instance name
      RdsMasterUsername:
        default: RDS username
      RdsMasterPassword:
        default: RDS password
      RdsInstanceClass:
        default: RDS instance type
      RdsStorage:
        default: RDS storage size (GB)
      MultiAzDatabase:
        default: Enable Multi-AZ RDS
Parameters:
  VpcID:
    Default: ${EKS_VPC_ID}
    Description: VpcId of the EKS cluster to deploy into
    Type: "AWS::EC2::VPC::Id"
  VpcIPCidr:
    Default: ${EKS_VPC_CIDR}
    Description: "Enter VPC CIDR that hosts the EKS cluster. Ex: 10.0.0.0/16"
    Type: String
  EksInstanceSubnets:
    Default: ${EKS_PRIVATE_SUBNETS}
    Type: "List<AWS::EC2::Subnet::Id>"
    Description: Select all the subnets EKS utilizes. Recommended approach is to use only private subnets
    ConstraintDescription: >-
      Password must be at least 9 characters long and have 3 out of the
      following: one number, one lower case, one upper case, or one special
      character.
  RdsInstanceName:
    Default: ${EKS_CLUSTER_NAME}db
    Description: ""
    Type: String
    MinLength: "1"
    MaxLength: "64"
    AllowedPattern: "[a-zA-Z][a-zA-Z0-9]*"
    ConstraintDescription: Must begin with a letter and between 1 and 64 alphanumeric characters.
  RdsMasterUsername:
    Description: Enter the master username for the RDS instance.
    Default: root
    Type: String
    MinLength: "1"
    MaxLength: "63"
    AllowedPattern: "^[a-zA-Z0-9]*$"
    ConstraintDescription: >-
      Must be 1 to 63 characters long, begin with a letter, contain only
      alphanumeric characters, and not be a reserved word by PostgreSQL engine.
  RdsMasterPassword:
    Default: "${RDS_DB_PASSWORD}"
    NoEcho: "true"
    Description: >-
      Enter the master password for the RDS instance. This password must contain
      8 to 128 characters and can be any printable ASCII character except @, /,
      or ".
    Type: String
    MinLength: "8"
    MaxLength: "128"
    AllowedPattern: >-
      ^((?=.*[0-9])(?=.*[a-z])(?=.*[A-Z])|(?=.*[0-9])(?=.*[a-z])(?=.*[!@#$%^&*])|(?=.*[0-9])(?=.*[A-Z])(?=.*[!@#$%^&*])|(?=.*[a-z])(?=.*[A-Z])(?=.*[!@#$%^&*])).{8,128}$
    ConstraintDescription: >-
      Password must be at least 9 characters long and have 3 out of the
      following: one number, one lower case, one upper case, or one special
      character.
  RdsInstanceClass:
    Description: ""
    Type: String
    Default: db.t2.medium
    AllowedValues:
      - db.t2.micro
      - db.t2.small
      - db.t2.medium
      - db.t2.large
      - db.t2.xlarge
      - db.t2.2xlarge
      - db.m4.large
      - db.m4.xlarge
      - db.m4.2xlarge
      - db.m4.4xlarge
      - db.m4.10xlarge
      - db.m4.16xlarge
      - db.r4.large
      - db.r4.xlarge
      - db.r4.2xlarge
      - db.r4.4xlarge
      - db.r4.8xlarge
      - db.r4.16xlarge
      - db.r3.large
      - db.r3.2xlarge
      - db.r3.4xlarge
      - db.r3.8xlarge
    ConstraintDescription: Must be a valid EC2 RDS instance type
  RdsStorage:
    Default: "40"
    Description: ""
    Type: Number
    MinValue: "40"
    MaxValue: "1024"
    ConstraintDescription: Must be set to between 40 and 1024GB.
  MultiAzDatabase:
    Default: "false"
    Description: ""
    Type: String
    AllowedValues:
      - "true"
      - "false"
    ConstraintDescription: Must be either true or false.
Resources:
  RdsInstance:
    Type: "AWS::RDS::DBInstance"
    DependsOn:
      - DbSecurityGroup
      - RdsInstanceSubnetGroup
    Properties:
      AllocatedStorage: !Ref RdsStorage
      AutoMinorVersionUpgrade: "false"
      VPCSecurityGroups:
        - !Ref DbSecurityGroup
      DBName: !Ref RdsInstanceName
      BackupRetentionPeriod: "7"
      DBInstanceIdentifier: !Ref RdsInstanceName
      DBInstanceClass: !Ref RdsInstanceClass
      DBSubnetGroupName: !Ref RdsInstanceSubnetGroup
      CopyTagsToSnapshot: true
      EnableCloudwatchLogsExports:
        - slowquery
      Engine: mariadb
      EngineVersion: 10.4
      MasterUsername: !Ref RdsMasterUsername
      MasterUserPassword: !Ref RdsMasterPassword
      MultiAZ: !Ref MultiAzDatabase
      StorageType: gp2
  RdsInstanceSubnetGroup:
    Type: "AWS::RDS::DBSubnetGroup"
    Properties:
      DBSubnetGroupDescription: Source subnet
      SubnetIds: !Ref EksInstanceSubnets
  # Create DB Security Group
  DbSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: For RDS Instance
      VpcId: !Ref VpcID
  # Attach Security Group Rule
  DbIngress1:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref DbSecurityGroup
      IpProtocol: tcp
      FromPort: "3306"
      ToPort: "3306"
      CidrIp: !Ref "VpcIPCidr"
Outputs:
  RdsInstanceEndpoint:
    Description: MariaDB endpoint
    Value: !GetAtt RdsInstance.Endpoint.Address
  RdsInstancePort:
    Description: MariaDB port
    Value: !GetAtt RdsInstance.Endpoint.Port
  RdsInstanceUser:
    Description: Username for the MariaDB instance
    Value: !Ref RdsMasterUsername
  RdsMasterPassword:
    Description: Password for the MariaDB instance
    Value: !Ref RdsMasterPassword
EOF

eval aws --region eu-central-1 cloudformation deploy --stack-name "${EKS_CLUSTER_NAME}-rds" \
  --template-file tmp/cf_rds.yml --tags ${TAGS}

RDS_DB_HOST=$(aws rds --region eu-central-1 describe-db-instances --query "DBInstances[?DBInstanceIdentifier==\`${EKS_CLUSTER_NAME}db\`].[Endpoint.Address]" --output text)
```

Output:

```text
Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - kube1-rds
```

Install [phpMyAdmin](https://www.phpmyadmin.net/):

```bash
helm install --version 6.5.4 --namespace phpmyadmin --create-namespace --values - phpmyadmin bitnami/phpmyadmin << EOF
db:
  allowArbitraryServer: false
  host: ${RDS_DB_HOST}
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://auth.${MY_DOMAIN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://auth.${MY_DOMAIN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - name: phpmyadmin.${MY_DOMAIN}
  tls: true
  tlsHosts:
    - phpmyadmin.${MY_DOMAIN}
  tlsSecret: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
metrics:
  enabled: true
EOF
```

Output:

```bash
NAME: phpmyadmin
LAST DEPLOYED: Sat Oct 24 16:58:32 2020
NAMESPACE: phpmyadmin
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
1. Get the application URL by running these commands:
  You should be able to access your new phpMyAdmin installation through
  https://your-cluster-ip


  Find out your cluster ip address by running:
  $ kubectl cluster-info



2. How to log in

phpMyAdmin has been configured to connect to a database in kube1db.crssduk1yxyx.eu-central-1.rds.amazonaws.comwith port 3306
Please login using a database username and password.

** Please be patient while the chart is being deployed **
```

### EFS

Install [Amazon EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver),
which supports ReadWriteMany PVC, is installed:

```bash
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/dev/?ref=master"
```

Apply CloudFormation template to create Amazon EFS.
The template below is inspired by: [https://github.com/so008mo/inkubator-play/blob/64a150dbdc35b9ade48ff21b9ae6ba2710d18b5d/roles/eks/files/amazon-eks-efs.yaml](https://github.com/so008mo/inkubator-play/blob/64a150dbdc35b9ade48ff21b9ae6ba2710d18b5d/roles/eks/files/amazon-eks-efs.yaml)

```bash
cat > tmp/cf_efs.yml << EOF
AWSTemplateFormatVersion: "2010-09-09"
Description: Create EFS, mount points, security groups for EKS
Parameters:
  VpcID:
    Default: ${EKS_VPC_ID}
    Description: VpcId of the EKS cluster to deploy into
    Type: "AWS::EC2::VPC::Id"
  SubnetId1:
    Default: ${EKS_PRIVATE_SUBNET1}
    Type: AWS::EC2::Subnet::Id
    Description: ID of private subnet in first AZ.
  SubnetId2:
    Default: ${EKS_PRIVATE_SUBNET2}
    Type: AWS::EC2::Subnet::Id
    Description: ID of private subnet in second AZ.
  FileSystemName:
    Default: ${EKS_CLUSTER_NAME}-efs
    Type: String
    Description: The name of the EFS file system.
  VpcIPCidr:
    Default: ${EKS_VPC_CIDR}
    Description: "Enter VPC CIDR that hosts the EKS cluster. Ex: 10.0.0.0/16"
    Type: String
Resources:
  MountTargetSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      VpcId:
        Ref: VpcID
      GroupName: ${EKS_CLUSTER_NAME}-efs-sf
      GroupDescription: Security group for mount target
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: "2049"
          ToPort: "2049"
          CidrIp:
            Ref: VpcIPCidr
      Tags:
        - Key: Name
          Value: ${EKS_CLUSTER_NAME}-efs-sf
  FileSystem:
    Type: AWS::EFS::FileSystem
    Properties:
      FileSystemTags:
      - Key: Name
        Value:
          Ref: FileSystemName
  MountTargetAZ1:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId:
        Ref: FileSystem
      SubnetId:
        Ref: SubnetId1
      SecurityGroups:
      - Ref: MountTargetSecurityGroup
  MountTargetAZ2:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId:
        Ref: FileSystem
      SubnetId:
        Ref: SubnetId2
      SecurityGroups:
      - Ref: MountTargetSecurityGroup
Outputs:
  OutputFileSystemId:
    Description: Id of Elastic File System
    Value:
      Ref: FileSystem
  OutputMountTarget1:
    Value:
      Ref: MountTargetAZ1
  OutputMountTarget2:
    Value:
      Ref: MountTargetAZ2
EOF

eval aws --region eu-central-1 cloudformation deploy --stack-name "${EKS_CLUSTER_NAME}-efs" \
  --template-file tmp/cf_efs.yml --tags ${TAGS}

EFS_FS_ID=$(aws efs --region eu-central-1 describe-file-systems --query "FileSystems[?Name==\`${EKS_CLUSTER_NAME}-efs\`].[FileSystemId]" --output text)
```

Output:

```text
Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - kube1-efs
```

Create storage class:

```bash
kubectl apply -f - << EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
EOF
```

Create ReadWriteMany persistent volume like described [here](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/multiple_pods/README.md):

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FS_ID}
EOF
```

### Drupal

Create `drupal` namespace and PVC:

```bash
kubectl create namespace drupal
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal-efs-pvc
  namespace: drupal
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 1Gi
EOF
```

Install Drupal:

```bash
helm repo add --force-update bitnami https://charts.bitnami.com/bitnami ; helm repo update > /dev/null
helm install --version 9.1.2 --namespace drupal --values - drupal bitnami/drupal << EOF
# https://github.com/bitnami/charts/blob/master/bitnami/drupal/values.yaml
replicaCount: 1
drupalSkipInstall: false
drupalUsername: myuser
drupalPassword: mypassword12345
drupalEmail: petr.ruzicka@gmail.com
externalDatabase:
  host: ${RDS_DB_HOST}
  user: root
  password: ${RDS_DB_PASSWORD}
  database: drupal
smtpHost:
smtpPort:
smtpUser:
smtpPassword:
smtpProtocol:
mariadb:
  enabled: false
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://auth.${MY_DOMAIN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://auth.${MY_DOMAIN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hostname: drupal.${MY_DOMAIN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - drupal.${MY_DOMAIN}
persistence:
  enabled: true
  storageClass: efs-sc
  accessMode: ReadWriteMany
  size: 1Gi
  existingClaim: drupal-efs-pvc
metrics:
  enabled: true
EOF
```
