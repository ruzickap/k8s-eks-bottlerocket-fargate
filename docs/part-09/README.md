# Drupal

Few notes about Drupal installation with RDS + EFS.

## Drupal installation

Get details about AWS environment where is the EKS cluster and store it into
variables:

```bash
RDS_DB_USERNAME="root"
```

### RDS

Apply CloudFormation template to create Amazon RDS MySQL database.
The template below is inspired by: [https://github.com/aquasecurity/marketplaces/blob/master/aws/cloudformation/AquaRDS.yaml](https://github.com/aquasecurity/marketplaces/blob/master/aws/cloudformation/AquaRDS.yaml)

```bash
cat > "tmp/${CLUSTER_FQDN}/cf_rds.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: This AWS CloudFormation template installs the AWS RDS MySQL database.
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
    Type: AWS::RDS::DBInstance
    DependsOn:
      - DbSecurityGroup
      - RdsInstanceSubnetGroup
    DeletionPolicy: Delete
    Properties:
      AllocatedStorage: !Ref RdsStorage
      AutoMinorVersionUpgrade: "true"
      VPCSecurityGroups:
        - !Ref DbSecurityGroup
      DBName: !Sub "${ClusterName}db"
      BackupRetentionPeriod: "0"
      DBInstanceIdentifier: !Sub "${ClusterName}db"
      DBInstanceClass: !Ref RdsInstanceClass
      DBSubnetGroupName: !Ref RdsInstanceSubnetGroup
      CopyTagsToSnapshot: true
      EnableCloudwatchLogsExports:
        - slowquery
      EnableIAMDatabaseAuthentication: true
      Engine: mysql
      EngineVersion: 8.0.23
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
    Description: MySQL endpoint
    Value: !GetAtt RdsInstance.Endpoint.Address
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RdsInstanceEndpoint"
  RdsInstancePort:
    Description: MySQL port
    Value: !GetAtt RdsInstance.Endpoint.Port
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RdsInstancePort"
  RdsInstanceUser:
    Description: Username for the MySQL instance
    Value: !Ref RdsMasterUsername
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RdsInstanceUser"
  RdsMasterPassword:
    Description: Password for the MySQL instance
    Value: !Ref RdsMasterPassword
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-RdsMasterPassword"
EOF

eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM --stack-name "${CLUSTER_NAME}-rds" --parameter-overrides "ClusterName=${CLUSTER_NAME} KmsKeyId=${KMS_KEY_ID} RdsMasterPassword=${MY_PASSWORD} RdsMasterUsername=${RDS_DB_USERNAME} VpcIPCidr=${EKS_VPC_CIDR}" --template-file "tmp/${CLUSTER_FQDN}/cf_rds.yml" --tags "${TAGS}"

RDS_DB_HOST=$(aws rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier==\`${CLUSTER_NAME}db\`].[Endpoint.Address]" --output text)
RDS_DB_RESOURCE_ID=$(aws rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier==\`${CLUSTER_NAME}db\`].DbiResourceId" --output text)
```

Initialize database:

```bash
kubectl get pods mysql-client-drupal || kubectl run --env MYSQL_PWD="${MY_PASSWORD}" --image=mysql:8.0 --restart=Never mysql-client-drupal -- \
  mysql -h "${RDS_DB_HOST}" -u "${RDS_DB_USERNAME}" -e "
    CREATE USER \"exporter\"@\"%\" IDENTIFIED BY \"${MY_PASSWORD}\" WITH MAX_USER_CONNECTIONS 3;
    CREATE USER \"drupal\"@\"%\" IDENTIFIED BY \"${MY_PASSWORD}\";
    CREATE USER \"drupal2\"@\"%\" IDENTIFIED BY \"${MY_PASSWORD}\";
    CREATE USER \"iamtest\"@\"%\" IDENTIFIED WITH AWSAuthenticationPlugin AS \"RDS\" REQUIRE SSL;
    CREATE DATABASE drupal;
    CREATE DATABASE drupal2;
    CREATE DATABASE iamtest;
    GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO \"exporter\"@\"%\";
    GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES ON drupal.* TO \"drupal\"@\"%\";
    GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES ON drupal2.* TO \"drupal2\"@\"%\";
    GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES ON iamtest.* TO \"iamtest\"@\"%\";
  "
```

### Prometheus MySQL Exporter

Install [Prometheus MySQL Exporter](https://github.com/prometheus/mysqld_exporter)
using Helm Chart.

Install `prometheus-mysql-exporter`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/prometheus-mysql-exporter)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-mysql-exporter/values.yaml).

```bash
helm upgrade --install --version 1.2.1 --namespace prometheus-mysql-exporter --create-namespace --values - prometheus-mysql-exporter prometheus-community/prometheus-mysql-exporter << EOF
serviceMonitor:
  enabled: true
mysql:
  host: "${RDS_DB_HOST}"
  pass: "${MY_PASSWORD}"
  user: "exporter"
EOF
```

### phpMyAdmin

Install [phpMyAdmin](https://www.phpmyadmin.net/) using Helm Chart.

Install `phpmyadmin`
[helm chart](https://artifacthub.io/packages/helm/bitnami/phpmyadmin)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/phpmyadmin/values.yaml).

```bash
helm upgrade --install --version 8.2.11 --namespace phpmyadmin --create-namespace --values - phpmyadmin bitnami/phpmyadmin << EOF
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
$(curl -s "https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem" | sed "s/^/      /")
EOF
```

### Connect to the DB using IAM role

Try to connect to the MySQL database from Kubernetes pod using IAM role:

* [How do I allow users to authenticate to an Amazon RDS MySQL DB instance using their IAM credentials?](https://repost.aws/knowledge-center/users-connect-rds-iam)
* [AWS/EKS: Support for IAM authentication](https://github.com/prometheus-community/postgres_exporter/issues/326)

Create Service Account `rds-sa` for accessing the MySQL RDS DB :

```bash
sed -i "/  serviceAccounts:/a \
\ \ \ \ - metadata: \n\
        name: rds-sa \n\
        namespace: default \n\
      attachPolicy: \n\
        Version: 2012-10-17 \n\
        Statement: \n\
          Effect: Allow \n\
          Action: \n\
            - rds-db:connect \n\
          Resource: \n\
            - arn:aws:rds-db:${AWS_DEFAULT_REGION}:*:dbuser:${RDS_DB_RESOURCE_ID}/iamtest
" "tmp/${CLUSTER_FQDN}/eksctl.yaml"

eksctl create iamserviceaccount --config-file "tmp/${CLUSTER_FQDN}/eksctl.yaml" --approve
```

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  name: mysql-iam-test
spec:
  serviceAccountName: rds-sa
  containers:
  - name: ubuntu
    image: ubuntu:20.04
    command:
      - /bin/bash
      - -c
      - |
        set -x
        apt update
        apt install -y unzip less mysql-client wget telnet &> /dev/null
        wget -q "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -O "awscliv2.zip"
        unzip awscliv2.zip > /dev/null
        ./aws/install
        aws sts get-caller-identity
        wget -q https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem
        TOKEN="\$(aws rds generate-db-auth-token --hostname ${RDS_DB_HOST} --port 3306 --region ${AWS_DEFAULT_REGION} --username iamtest)"
        mysql -h "${RDS_DB_HOST}" -u "iamtest" --password="${MY_PASSWORD}" -e "show databases;"
        mysql -h "${RDS_DB_HOST}" -u "iamtest" --password="\${TOKEN}" --enable-cleartext-plugin --ssl-ca=rds-ca-2019-root.pem -e "show databases;"
        mysql -h "${RDS_DB_HOST}" -u "iamtest" --password="\${TOKEN}" --enable-cleartext-plugin --ssl-ca=amazon-root-CA-1.pem --ssl-mode=REQUIRED -e "show databases;"
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
  restartPolicy: Never
EOF
sleep 50
```

Check the logs:

```bash
kubectl logs mysql-iam-test --tail=5
```

Output:

```text
+ aws sts get-caller-identity
{
    "UserId": "xxxxxxxxxxxxxxxxxxxxx:botocore-session-1638296138",
    "Account": "7xxxxxxxxxx7",
    "Arn": "arn:aws:sts::7xxxxxxxxxx7:assumed-role/eksctl-kube1-addon-iamserviceaccount-default-Role1-ZOKCKAOF74H0/botocore-session-1638296138"
}
+ wget -q https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem
++ aws rds generate-db-auth-token --hostname kube1db.cbpu7ikafk2a.eu-west-1.rds.amazonaws.com --port 3306 --region eu-west-1 --username iamtest
+ TOKEN='kube1db.cbpu7ikafk2a.eu-west-1.rds.amazonaws.com:3306/?Action=connect&DBUser=iamtest&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=xxxxxxxxxxxxxxxxxxxx%2F20211130%2Feu-west-1%2Frds-db%2Faws4_request&X-Amz-Date=20211130T181540Z&X-Amz-Expires=900&X-Amz-SignedHeaders=host&X-Amz-Security-Token=IQo...6e917'
+ mysql -h kube1db.cbpu7ikafk2a.eu-west-1.rds.amazonaws.com -u iamtest --password=MyAdmin123,. -e 'show databases;'
mysql: [Warning] Using a password on the command line interface can be insecure.
ERROR 2059 (HY000): Authentication plugin 'mysql_clear_password' cannot be loaded: plugin not enabled
+ mysql -h kube1db.cbpu7ikafk2a.eu-west-1.rds.amazonaws.com -u iamtest '--password=kube1db.cbpu7ikafk2a.eu-west-1.rds.amazonaws.com:3306/?Action=connect&DBUser=iamtest&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=xxxxxxxxxxxxxxxxxxxx%2F20211130%2Feu-west-1%2Frds-db%2Faws4_request&X-Amz-Date=20211130T181540Z&X-Amz-Expires=900&X-Amz-SignedHeaders=host&X-Amz-Security-Token=IQoJb3J...e917' --enable-cleartext-plugin --ssl-ca=rds-ca-2019-root.pem -e 'show databases;'
mysql: [Warning] Using a password on the command line interface can be insecure.
Database
iamtest
information_schema
+ mysql -h kube1db.cbpu7ikafk2a.eu-west-1.rds.amazonaws.com -u iamtest '--password=kube1db.cbpu7ikafk2a.eu-west-1.rds.amazonaws.com:3306/?Action=connect&DBUser=iamtest&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=xxxxxxxxxxxxxxxxxxxx%2F20211130%2Feu-west-1%2Frds-db%2Faws4_request&X-Amz-Date=20211130T181540Z&X-Amz-Expires=900&X-Amz-SignedHeaders=host&X-Amz-Security-Token=IQo...6e917' --enable-cleartext-plugin --ssl-ca=amazon-root-CA-1.pem --ssl-mode=REQUIRED -e 'show databases;'
mysql: [Warning] Using a password on the command line interface can be insecure.
WARNING: no verification of server certificate will be done. Use --ssl-mode=VERIFY_CA or VERIFY_IDENTITY.
Database
iamtest
information_schema
```

### Install Drupal

The variables containing `FileSystemId` and `AccessPointId` like
`EFS_FS_ID_DRUPAL` and `EFS_AP_ID_DRUPAL1`  were defined previously.

Create ReadWriteMany persistent volume like described [here](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/multiple_pods/README.md):

```bash
kubectl get namespace drupal &> /dev/null || kubectl create namespace drupal
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-drupal-pv
spec:
  storageClassName: efs-drupal-static
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Delete
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FS_ID_DRUPAL}::${EFS_AP_ID_DRUPAL1}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal-efs-pvc
  namespace: drupal
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-drupal-static
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
helm repo add --force-update bitnami https://charts.bitnami.com/bitnami
helm upgrade --install --version 10.2.24 --namespace drupal --values - drupal bitnami/drupal << EOF
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
  # storageClass: efs-drupal
  # accessMode: ReadWriteMany
  # size: 1Gi
  existingClaim: drupal-efs-pvc
EOF
```

### Install Drupal2

The variables containing `FileSystemId` and `AccessPointId` like
`EFS_FS_ID_DRUPAL` and `EFS_AP_ID_DRUPAL2` were defined previously.

Create ReadWriteMany persistent volume like described [here](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/multiple_pods/README.md):

```bash
kubectl get namespace drupal2 &> /dev/null || kubectl create namespace drupal2
kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-drupal2-pv
spec:
  storageClassName: efs-drupal-static
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Delete
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FS_ID_DRUPAL}::${EFS_AP_ID_DRUPAL2}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal2-efs-pvc
  namespace: drupal2
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-drupal-static
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
helm upgrade --install --version 10.2.24 --namespace drupal2 --values - drupal2 bitnami/drupal << EOF
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
