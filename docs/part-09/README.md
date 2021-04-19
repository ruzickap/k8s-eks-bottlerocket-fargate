# Drupal

Few notes about Drupal installation with RDS + EFS.

## Drupal installation

Get details about AWS environment where is the EKS cluster and store it into
variables:

```bash
RDS_DB_USERNAME="root"
```

### RDS

Apply CloudFormation template to create Amazon RDS MariaDB database.
The template below is inspired by: [https://github.com/aquasecurity/marketplaces/blob/master/aws/cloudformation/AquaRDS.yaml](https://github.com/aquasecurity/marketplaces/blob/master/aws/cloudformation/AquaRDS.yaml)

```bash
cat > "tmp/${CLUSTER_FQDN}/cf_rds.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: This AWS CloudFormation template installs the AWS RDS MariaDB database.
Parameters:
  ClusterName:
    Default: "kube1"
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
  DBMonitoringRole:
    Type: AWS::IAM::Role
    Properties:
      Path: "/"
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole
      AssumeRolePolicyDocument:
        Version: 2012-10-17
        Statement:
          - Effect: Allow
            Principal:
              Service:
                - monitoring.rds.amazonaws.com
            Action:
              - sts:AssumeRole
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
      MonitoringInterval: 60
      MonitoringRoleArn: !GetAtt DBMonitoringRole.Arn
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

eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM --stack-name "${CLUSTER_NAME}-rds" --parameter-overrides "ClusterName=${CLUSTER_NAME} KmsKeyId=${EKS_KMS_KEY_ID} RdsMasterPassword=${MY_PASSWORD} RdsMasterUsername=${RDS_DB_USERNAME} VpcIPCidr=${EKS_VPC_CIDR}" --template-file "tmp/${CLUSTER_FQDN}/cf_rds.yml" --tags "${TAGS}"

RDS_DB_HOST=$(aws rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier==\`${CLUSTER_NAME}db\`].[Endpoint.Address]" --output text)
```

Initialize database:

```bash
kubectl run --env MYSQL_PWD=${MY_PASSWORD} --image=mysql:8.0 --restart=Never mysql-client-drupal -- \
  mysql -h "${RDS_DB_HOST}" -u "${RDS_DB_USERNAME}" -e "
    CREATE USER \"drupal\"@\"%\" IDENTIFIED BY \"${MY_PASSWORD}\";
    CREATE USER \"drupal2\"@\"%\" IDENTIFIED BY \"${MY_PASSWORD}\";
    CREATE DATABASE drupal;
    CREATE DATABASE drupal2;
    GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES ON drupal.* TO \"drupal\"@\"%\";
    GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES ON drupal.* TO \"drupal2\"@\"localhost\";
  "
```

### phpMyAdmin

Install [phpMyAdmin](https://www.phpmyadmin.net/) using Helm Chart

Install `phpmyadmin`
[helm chart](https://artifacthub.io/packages/helm/bitnami/phpmyadmin)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/phpmyadmin/values.yaml).

```bash
helm install --version 8.2.4 --namespace phpmyadmin --create-namespace --values - phpmyadmin bitnami/phpmyadmin << EOF
ingress:
  enabled: true
  hostname: phpmyadmin.${CLUSTER_FQDN}
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  extraTls:
  - hosts:
      - phpmyadmin.${CLUSTER_FQDN}
    secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
db:
  allowArbitraryServer: false
  host: ${RDS_DB_HOST}
  enableSsl: true
  ssl:
    caCertificate: |-
$(curl -s "https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem" | sed  "s/^/      /" )
EOF
```

### Install Drupal

Get the `FileSystemId` from EFS:

```bash
EFS_AP_DRUPAL_ID=$(aws efs describe-access-points --query "AccessPoints[?(FileSystemId==\`${EFS_FS_ID}\` && RootDirectory.Path==\`/drupal\`)].[AccessPointId]" --output text)
```

Create ReadWriteMany persistent volume like described [here](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/multiple_pods/README.md):

```bash
kubectl create namespace drupal
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-drupal-pv
spec:
  storageClassName: efs-static-sc
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Delete
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FS_ID}::${EFS_AP_DRUPAL_ID}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal-efs-pvc
  namespace: drupal
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-static-sc
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
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install --version 10.2.10 --namespace drupal --values - drupal bitnami/drupal << EOF
replicaCount: 2
drupalUsername: admin
drupalPassword: ${MY_PASSWORD}
drupalEmail: ${MY_EMAIL}
externalDatabase:
  host: ${RDS_DB_HOST}
  user: drupal
  password: ${MY_PASSWORD}
  database: drupal
smtpHost: mailhog.mailhog.svc.cluster.local
smtpPort: 1025
smtpUser: "x"
smtpPassword: "x"
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
  # EFS dynamic provisioning can not be used due to UID/GID issue when EFS assign
  # randomly GID to the NFS share and then Drupal can not write to it
  # (chown to such directory is not working - prohibited by AWS)
  # storageClass: efs-dynamic-sc
  # accessMode: ReadWriteMany
  # size: 1Gi
  existingClaim: drupal-efs-pvc
EOF
```

### Install Drupal2

Get the `FileSystemId` from EFS:

```bash
EFS_AP_DRUPAL2_ID=$(aws efs describe-access-points --query "AccessPoints[?(FileSystemId==\`${EFS_FS_ID}\` && RootDirectory.Path==\`/drupal2\`)].[AccessPointId]" --output text)
```

Create ReadWriteMany persistent volume like described [here](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/multiple_pods/README.md):

```bash
kubectl create namespace drupal2
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-drupal2-pv
spec:
  storageClassName: efs-static-sc
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Delete
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FS_ID}::${EFS_AP_DRUPAL2_ID}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal2-efs-pvc
  namespace: drupal2
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-static-sc
  volumeName: efs-drupal2-pv
  resources:
    requests:
      storage: 1Gi
EOF
```

Enable Istio for namespace `drupal2`:

```bash
kubectl label namespace drupal2 istio-injection=enabled kiali.io/member-of=kiali --overwrite
```

Install `drupal2`:

```bash
helm install --version 10.2.10 --namespace drupal2 --values - drupal2 bitnami/drupal << EOF
replicaCount: 2
drupalUsername: admin
drupalPassword: ${MY_PASSWORD}
drupalEmail: ${MY_EMAIL}
commonLabels:
  app: "{{ .Release.Name }}"
  version: "{{ .Chart.AppVersion }}"
externalDatabase:
  host: ${RDS_DB_HOST}
  user: drupal2
  password: ${MY_PASSWORD}
  database: drupal2
smtpHost: mailhog.mailhog.svc.cluster.local
smtpPort: 1025
smtpUser: "x"
smtpPassword: "x"
mariadb:
  enabled: false
service:
  type: ClusterIP
persistence:
  enabled: true
  existingClaim: drupal2-efs-pvc
EOF
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
hey -n 2000 -c 1 -q 1 -h2 "https://drupal2.${CLUSTER_FQDN}" > /dev/null &
```
