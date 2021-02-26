# Drupal

Few notes about Drupal installation with RDS + EFS.

## Drupal installation

Get details about AWS environment where is the EKS cluster and store it into
variables:

```bash
EKS_VPC_ID=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text)
EKS_VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "${EKS_VPC_ID}" --query "Vpcs[].CidrBlock" --output text)
RDS_DB_USERNAME="root"
RDS_DB_PASSWORD="123-My_Secret_Password-456"
```

### RDS

Apply CloudFormation template to create Amazon RDS MariaDB database.
The template below is inspired by: [https://github.com/aquasecurity/marketplaces/blob/master/aws/cloudformation/AquaRDS.yaml](https://github.com/aquasecurity/marketplaces/blob/master/aws/cloudformation/AquaRDS.yaml)

```bash
cat > tmp/cf_rds.yml << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: This AWS CloudFormation template installs the AWS RDS MariaDB database.
Parameters:
  ClusterName:
    Default: "k1"
    Description: K8s Cluster name
    Type: String
  KmsKeyId:
    Description: The ARN of the AWS Key Management Service (AWS KMS) master key that is used to encrypt the DB instance
    Type: String
  MultiAzDatabase:
    Default: "false"
    Type: String
    AllowedValues:
      - "true"
      - "false"
    ConstraintDescription: Must be either true or false.
  RdsMasterUsername:
    Description: Enter the master username for the RDS instance.
    Type: String
    MinLength: "1"
    MaxLength: "63"
    AllowedPattern: "^[a-zA-Z0-9]*$"
    ConstraintDescription: >-
      Must be 1 to 63 characters long, begin with a letter, contain only
      alphanumeric characters, and not be a reserved word by PostgreSQL engine.
  RdsInstanceClass:
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
  RdsMasterPassword:
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
  RdsStorage:
    Default: "40"
    Type: Number
    MinValue: "40"
    MaxValue: "1024"
    ConstraintDescription: Must be set to between 40 and 1024GB.
  VpcIPCidr:
    Description: "Enter VPC CIDR that hosts the EKS cluster. Ex: 10.0.0.0/16"
    Type: String
Resources:
  RdsInstance:
    Type: "AWS::RDS::DBInstance"
    DependsOn:
      - DbSecurityGroup
      - RdsInstanceSubnetGroup
    DeletionPolicy: Delete
    Properties:
      AllocatedStorage: !Ref RdsStorage
      AutoMinorVersionUpgrade: "false"
      VPCSecurityGroups:
        - !Ref DbSecurityGroup
      DBName: !Sub "${ClusterName}db"
      BackupRetentionPeriod: "0"
      DBInstanceIdentifier: !Sub "${ClusterName}db"
      DBInstanceClass: !Ref RdsInstanceClass
      DBSubnetGroupName: !Ref RdsInstanceSubnetGroup
      CopyTagsToSnapshot: true
      EnableCloudwatchLogsExports:
        - general
        - slowquery
      Engine: mariadb
      EngineVersion: 10.5
      KmsKeyId: !Ref KmsKeyId
      MasterUsername: !Ref RdsMasterUsername
      MasterUserPassword: !Ref RdsMasterPassword
      MultiAZ: !Ref MultiAzDatabase
      StorageEncrypted: true
      # gp3 is not supported yet (2021-01-30)
      StorageType: gp2
  RdsInstanceSubnetGroup:
    Type: "AWS::RDS::DBSubnetGroup"
    Properties:
      DBSubnetGroupDescription: Source subnet
      SubnetIds:
      - Fn::Select:
        - 0
        - Fn::Split:
          - ","
          - Fn::ImportValue: !Sub "eksctl-${ClusterName}-cluster::SubnetsPrivate"
      - Fn::Select:
        - 1
        - Fn::Split:
          - ","
          - Fn::ImportValue: !Sub "eksctl-${ClusterName}-cluster::SubnetsPrivate"
  # Create DB Security Group
  DbSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: For RDS Instance
      VpcId:
        Fn::ImportValue:
          Fn::Sub: "eksctl-${ClusterName}-cluster::VPC"
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
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RdsInstanceEndpoint"
  RdsInstancePort:
    Description: MariaDB port
    Value: !GetAtt RdsInstance.Endpoint.Port
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RdsInstancePort"
  RdsInstanceUser:
    Description: Username for the MariaDB instance
    Value: !Ref RdsMasterUsername
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RdsInstanceUser"
  RdsMasterPassword:
    Description: Password for the MariaDB instance
    Value: !Ref RdsMasterPassword
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RdsMasterPassword"
EOF

eval aws cloudformation deploy --stack-name "${CLUSTER_NAME}-rds" --parameter-overrides "ClusterName=${CLUSTER_NAME} KmsKeyId=${EKS_KMS_KEY_ID} RdsMasterPassword=${RDS_DB_PASSWORD} RdsMasterUsername=${RDS_DB_USERNAME} VpcIPCidr=${EKS_VPC_CIDR}" --template-file tmp/cf_rds.yml --tags "${TAGS}"

RDS_DB_HOST=$(aws rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier==\`${CLUSTER_NAME}db\`].[Endpoint.Address]" --output text)
```

Output:

```text
Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - kube1-rds
```

Install [phpMyAdmin](https://www.phpmyadmin.net/) using Helm Chart

Install `phpmyadmin`
[helm chart](https://artifacthub.io/packages/helm/bitnami/phpmyadmin)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/phpmyadmin/values.yaml).

```bash
helm install --version 6.5.4 --namespace phpmyadmin --create-namespace --values - phpmyadmin bitnami/phpmyadmin << EOF
serviceMonitor:
  enabled: true
db:
  allowArbitraryServer: false
  host: ${RDS_DB_HOST}
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - name: phpmyadmin.${CLUSTER_FQDN}
  tls: true
  tlsHosts:
    - phpmyadmin.${CLUSTER_FQDN}
  tlsSecret: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
metrics:
  enabled: true
EOF
```

Output:

```text
NAME: phpmyadmin
LAST DEPLOYED: Thu Dec 10 16:09:35 2020
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

phpMyAdmin has been configured to connect to a database in k1db.crssduk1yxyx.eu-central-1.rds.amazonaws.comwith port 3306
Please login using a database username and password.

** Please be patient while the chart is being deployed **
```

### EFS

The [Amazon EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver)
supports ReadWriteMany PVC.

Apply CloudFormation template to create Amazon EFS.
The template below is inspired by: [https://github.com/so008mo/inkubator-play/blob/64a150dbdc35b9ade48ff21b9ae6ba2710d18b5d/roles/eks/files/amazon-eks-efs.yaml](https://github.com/so008mo/inkubator-play/blob/64a150dbdc35b9ade48ff21b9ae6ba2710d18b5d/roles/eks/files/amazon-eks-efs.yaml)

```bash
cat > tmp/cf_efs.yml << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Create EFS, mount points, security groups for EKS
Parameters:
  ClusterName:
    Description: "K8s Cluster name. Ex: k1"
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
          Permissions: "0775"
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
          Permissions: "0775"
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

eval aws cloudformation deploy --stack-name "${CLUSTER_NAME}-efs" --parameter-overrides "ClusterName=${CLUSTER_NAME} KmsKeyId=${EKS_KMS_KEY_ID} VpcIPCidr=${EKS_VPC_CIDR}" --template-file tmp/cf_efs.yml --tags "${TAGS}"

EFS_FS_ID=$(aws efs describe-file-systems --query "FileSystems[?Name==\`${CLUSTER_NAME}-efs\`].[FileSystemId]" --output text)
EFS_AP_DRUPAL_ID=$(aws efs describe-access-points --query "AccessPoints[?(FileSystemId==\`${EFS_FS_ID}\` && RootDirectory.Path==\`/drupal\`)].[AccessPointId]" --output text)
EFS_AP_DRUPAL2_ID=$(aws efs describe-access-points --query "AccessPoints[?(FileSystemId==\`${EFS_FS_ID}\` && RootDirectory.Path==\`/drupal2\`)].[AccessPointId]" --output text)
```

Output:

```text
Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - kube1-efs
```

### Install Drupal

Create ReadWriteMany persistent volume like described [here](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/multiple_pods/README.md):

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-drupal-pv
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FS_ID}::${EFS_AP_DRUPAL_ID}
EOF
```

Create `drupal` database inside MariaDB:

```bash
kubectl create namespace drupal
kubectl run -n drupal --env MYSQL_PWD=${RDS_DB_PASSWORD} --image=mysql:8.0 --restart=Never mysql-client-drupal -- \
  mysql -h "${RDS_DB_HOST}" -u "${RDS_DB_USERNAME}" -e "CREATE DATABASE drupal"
```

Create `drupal` namespace and PVC:

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal-efs-pvc
  namespace: drupal
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs
  volumeName: efs-drupal-pv
  resources:
    requests:
      storage: 1Gi
EOF
```

Install `drupal`
[helm chart](https://artifacthub.io/packages/helm/bitnami/drupal)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/drupal/values.yaml).

```bash
DRUPAL_USERNAME="mydrupaluser"
DRUPAL_PASSWORD="mypassword12345"

helm repo add bitnami https://charts.bitnami.com/bitnami
helm install --version 10.1.1 --namespace drupal --values - drupal bitnami/drupal << EOF
replicaCount: 2
drupalUsername: ${DRUPAL_USERNAME}
drupalPassword: ${DRUPAL_PASSWORD}
drupalEmail: ${MY_EMAIL}
externalDatabase:
  host: ${RDS_DB_HOST}
  user: ${RDS_DB_USERNAME}
  password: ${RDS_DB_PASSWORD}
  database: drupal
mariadb:
  enabled: false
service:
  type: ClusterIP
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hostname: drupal.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - drupal.${CLUSTER_FQDN}
persistence:
  enabled: true
  storageClass: efs
  accessMode: ReadWriteMany
  size: 1Gi
  existingClaim: drupal-efs-pvc
metrics:
  enabled: true
EOF
```

Output:

```text
"bitnami" has been added to your repositories
NAME: drupal
LAST DEPLOYED: Thu Dec 10 16:12:00 2020
NAMESPACE: drupal
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
*******************************************************************
*** PLEASE BE PATIENT: Drupal may take a few minutes to install ***
*******************************************************************

1. Get the Drupal URL:

  You should be able to access your new Drupal installation through

  http://drupal.k1.k8s.mylabs.dev/

2. Get your Drupal login credentials by running:

  echo Username: myuser
  echo Password: $(kubectl get secret --namespace drupal drupal -o jsonpath="{.data.drupal-password}" | base64 --decode)
```

### Install Drupal2

Create ReadWriteMany persistent volume like described [here](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/multiple_pods/README.md):

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-drupal2-pv
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FS_ID}::${EFS_AP_DRUPAL2_ID}
EOF
```

Create `drupal2` database inside MariaDB:

```bash
kubectl create namespace drupal2
kubectl label namespace drupal2 istio-injection=enabled kiali.io/member-of=kiali --overwrite
kubectl run -n drupal2 --env MYSQL_PWD=${RDS_DB_PASSWORD} --image=mysql:8--restart=Never mysql-client-drupal2 -- /bin/bash -c "
  sleep 5 && mysql -h \"${RDS_DB_HOST}\" -u \"${RDS_DB_USERNAME}\" -e \"CREATE DATABASE drupal2\""
```

Create `drupal2` namespace and PVC:

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal2-efs-pvc
  namespace: drupal2
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs
  volumeName: efs-drupal2-pv
  resources:
    requests:
      storage: 1Gi
EOF
```

Install `drupal`
[helm chart](https://artifacthub.io/packages/helm/bitnami/drupal)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/drupal/values.yaml).

```bash
DRUPAL2_USERNAME="mydrupal2user"
DRUPAL2_PASSWORD="mypassword12345"

helm repo add bitnami https://charts.bitnami.com/bitnami
helm install --version 10.1.1 --namespace drupal2 --values - drupal2 bitnami/drupal << EOF
replicaCount: 2
drupalUsername: ${DRUPAL2_USERNAME}
drupalPassword: ${DRUPAL2_PASSWORD}
drupalEmail: ${MY_EMAIL}
commonLabels:
  app: "{{ .Release.Name }}"
  version: "{{ .Chart.AppVersion }}"
externalDatabase:
  host: ${RDS_DB_HOST}
  user: ${RDS_DB_USERNAME}
  password: ${RDS_DB_PASSWORD}
  database: drupal2
mariadb:
  enabled: false
service:
  type: ClusterIP
persistence:
  enabled: true
  storageClass: efs
  accessMode: ReadWriteMany
  size: 1Gi
  existingClaim: drupal2-efs-pvc
metrics:
  enabled: true
EOF
```

Output:

```text
```

Create Istio components to allow accessing Drupal:

```bash
kubectl apply -f - << EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: drupal-destination-rule
  namespace: drupal2
spec:
  host: drupal2.drupal2.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: drupal2-virtual-service
  namespace: drupal2
spec:
  hosts:
    - drupal2.${CLUSTER_FQDN}
  gateways:
    - drupal2-gateway
  http:
    - route:
        - destination:
            host: drupal2.drupal2.svc.cluster.local
            port:
              number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: drupal2-gateway
  namespace: drupal2
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https-drupal2
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - drupal2.${CLUSTER_FQDN}
EOF
```

Generate traffic going to Drupal2:

```bash
hey -n 2000 -c 1 -q 1 -h2 https://drupal2.${CLUSTER_FQDN} > /dev/null &
```
