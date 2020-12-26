# Velero

Velero helps with backup/restore of Kubernetes objects.

Install `velero`
[helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
and modify the
[default values](https://github.com/vmware-tanzu/helm-charts/blob/main/charts/velero/values.yaml).

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install --version 2.14.1 --namespace velero --create-namespace --values - velero vmware-tanzu/velero << EOF
initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.1.0
    imagePullPolicy: Always
    volumeMounts:
      - mountPath: /target
        name: plugins
  - name: velero-plugin-for-csi
    image: velero/velero-plugin-for-csi:v0.1.2
    imagePullPolicy: Always
    volumeMounts:
      - mountPath: /target
        name: plugins
metrics:
  serviceMonitor:
    enabled: true
configuration:
  provider: aws
  backupStorageLocation:
    bucket: ${CLUSTER_FQDN}
    prefix: velero
    config:
      region: ${AWS_DEFAULT_REGION}
      kmsKeyId: ${KMS_KEY_ID}
  volumeSnapshotLocation:
    name: aws
    config:
      region: ${AWS_DEFAULT_REGION}
  features: EnableCSI
# IRSA not working due to bug: https://github.com/vmware-tanzu/velero/issues/2198
# serviceAccount:
#   server:
#     annotations:
#       eks.amazonaws.com/role-arn: ${S3_POLICY_ARN}
# This should be removed in favor of IRSA (see above)
credentials:
  secretContents:
    cloud: |
      [default]
      aws_access_key_id=${AWS_ACCESS_KEY_ID}
      aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF
```

Output:

```text
"vmware-tanzu" has been added to your repositories
NAME: velero
LAST DEPLOYED: Wed Dec 23 17:34:57 2020
NAMESPACE: velero
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Check that the velero is up and running:

    kubectl get deployment/velero -n velero

Check that the secret has been created:

    kubectl get secret/velero -n velero

Once velero server is up and running you need the client before you can use it
1. wget https://github.com/vmware-tanzu/velero/releases/download/v1.5.2/velero-v1.5.2-darwin-amd64.tar.gz
2. tar -xvf velero-v1.5.2-darwin-amd64.tar.gz -C velero-client

More info on the official site: https://velero.io/docs
```

## Backup

Run backup of `vault` namespace:

```bash
velero backup create backup-vault --ttl 24h --include-namespaces=vault --wait
```

Output:

```text
Backup request "backup-vault" submitted successfully.
Waiting for backup to complete. You may safely press ctrl-c to stop waiting - your backup will continue in the background.
..............................................................................
Backup completed with status: Completed. You may check for more information using the commands `velero backup describe backup-vault` and `velero backup logs backup-vault`.
```

Check the backups:

```bash
velero get backups
```

Output:

```text
NAME           STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
backup-vault   Completed   0        0          2020-12-26 06:13:08 +0100 CET   23h       default            <none>
```

See the details of the `backup-vault`:

```bash
velero backup describe backup-vault --details --features=EnableCSI
```

Output:

```text
Name:         backup-vault
Namespace:    velero
Labels:       velero.io/storage-location=default
Annotations:  velero.io/source-cluster-k8s-gitversion=v1.18.9-eks-d1db3c
              velero.io/source-cluster-k8s-major-version=1
              velero.io/source-cluster-k8s-minor-version=18+

Phase:  Completed

Errors:    0
Warnings:  0

Namespaces:
  Included:  vault
  Excluded:  <none>

Resources:
  Included:        *
  Excluded:        <none>
  Cluster-scoped:  auto

Label selector:  <none>

Storage Location:  default

Velero-Native Snapshot PVs:  auto

TTL:  24h0m0s

Hooks:  <none>

Backup Format Version:  1.1.0

Started:    2020-12-26 06:13:08 +0100 CET
Completed:  2020-12-26 06:13:53 +0100 CET

Expiration:  2020-12-27 06:13:05 +0100 CET

Total items to be backed up:  58
Items backed up:              58

Resource List:
  apps/v1/ControllerRevision:
    - vault/vault-7b9d5599f4
  apps/v1/Deployment:
    - vault/vault-agent-injector
  apps/v1/ReplicaSet:
    - vault/vault-agent-injector-6fcf464c66
  apps/v1/StatefulSet:
    - vault/vault
  discovery.k8s.io/v1beta1/EndpointSlice:
    - vault/vault-agent-injector-svc-nl8xk
    - vault/vault-brzgc
    - vault/vault-internal-w54xh
  extensions/v1beta1/Ingress:
    - vault/vault
  networking.k8s.io/v1beta1/Ingress:
    - vault/vault
  rbac.authorization.k8s.io/v1/ClusterRole:
    - system:auth-delegator
    - vault-agent-injector-clusterrole
  rbac.authorization.k8s.io/v1/ClusterRoleBinding:
    - vault-agent-injector-binding
    - vault-server-binding
  snapshot.storage.k8s.io/v1/VolumeSnapshot:
    - vault/velero-data-vault-0-q6ckf
  snapshot.storage.k8s.io/v1/VolumeSnapshotClass:
    - csi-ebs-snapclass
  snapshot.storage.k8s.io/v1/VolumeSnapshotContent:
    - snapcontent-5660caf3-c063-423f-a84d-646ec1b8329a
  v1/ConfigMap:
    - vault/vault-config
  v1/Endpoints:
    - vault/vault
    - vault/vault-agent-injector-svc
    - vault/vault-internal
  v1/Event:
    - vault/data-vault-0.16542b91145d992e
    - vault/data-vault-0.16542b9114c55aa8
    - vault/data-vault-0.16542b91e49f76fc
    - vault/vault-0.16542b9115e65e8e
    - vault/vault-0.16542b92e69477aa
    - vault/vault-0.16542b936a00120c
    - vault/vault-0.16542b9500c6724d
    - vault/vault-0.16542b96079f5da3
    - vault/vault-0.16542b961c4d8f44
    - vault/vault-0.16542b9626ca176c
    - vault/vault-0.16542b9738f052ae
    - vault/vault-agent-injector-6fcf464c66-pvf5h.16542b910eebeb0c
    - vault/vault-agent-injector-6fcf464c66-pvf5h.16542b9182c83ebf
    - vault/vault-agent-injector-6fcf464c66-pvf5h.16542b92143fb8c9
    - vault/vault-agent-injector-6fcf464c66-pvf5h.16542b921bf6b36b
    - vault/vault-agent-injector-6fcf464c66-pvf5h.16542b9225dcf248
    - vault/vault-agent-injector-6fcf464c66.16542b910e90441c
    - vault/vault-agent-injector.16542b910bbf7f37
    - vault/vault.16542b91130c8c78
    - vault/vault.16542b9114c76529
    - vault/vault.16542b9118f4026b
  v1/Namespace:
    - vault
  v1/PersistentVolume:
    - pvc-7c56c4b4-197a-4d0c-b6a5-0d1899965f8e
  v1/PersistentVolumeClaim:
    - vault/data-vault-0
  v1/Pod:
    - vault/vault-0
    - vault/vault-agent-injector-6fcf464c66-pvf5h
  v1/Secret:
    - vault/default-token-6qgnt
    - vault/eks-creds
    - vault/ingress-cert-staging
    - vault/sh.helm.release.v1.vault.v1
    - vault/vault-agent-injector-token-qzdvw
    - vault/vault-token-vqnvc
  v1/Service:
    - vault/vault
    - vault/vault-agent-injector-svc
    - vault/vault-internal
  v1/ServiceAccount:
    - vault/default
    - vault/vault
    - vault/vault-agent-injector

Velero-Native Snapshots: <none included>

CSI Volume Snapshots:
Snapshot Content Name: snapcontent-5660caf3-c063-423f-a84d-646ec1b8329a
  Storage Snapshot ID: snap-062a339572ef37867
  Snapshot Size (bytes): 1073741824
  Ready to use: false
```

List all the `VolumeSnapshot` objects:

```bash
kubectl get volumesnapshots --all-namespaces
```

Output:

```text
NAMESPACE   NAME                        READYTOUSE   SOURCEPVC      SOURCESNAPSHOTCONTENT   RESTORESIZE   SNAPSHOTCLASS       SNAPSHOTCONTENT                                    CREATIONTIME   AGE
vault       velero-data-vault-0-q6ckf   false        data-vault-0                           1Gi           csi-ebs-snapclass   snapcontent-5660caf3-c063-423f-a84d-646ec1b8329a   5s             42s
```

Check the `VolumeSnapshot` details:

```bash
kubectl describe volumesnapshots -n vault
```

Output:

```text
Name:         velero-data-vault-0-q6ckf
Namespace:    vault
Labels:       velero.io/backup-name=backup-vault
Annotations:  <none>
API Version:  snapshot.storage.k8s.io/v1
Kind:         VolumeSnapshot
Metadata:
  Creation Timestamp:  2020-12-26T05:13:13Z
  Finalizers:
    snapshot.storage.kubernetes.io/volumesnapshot-as-source-protection
  Generate Name:  velero-data-vault-0-
  Generation:     1
  Managed Fields:
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:generateName:
        f:labels:
          .:
          f:velero.io/backup-name:
      f:spec:
        .:
        f:source:
          .:
          f:persistentVolumeClaimName:
        f:volumeSnapshotClassName:
    Manager:      velero-plugin-for-csi
    Operation:    Update
    Time:         2020-12-26T05:13:13Z
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:finalizers:
      f:status:
        .:
        f:boundVolumeSnapshotContentName:
        f:creationTime:
        f:readyToUse:
        f:restoreSize:
    Manager:         snapshot-controller
    Operation:       Update
    Time:            2020-12-26T05:13:51Z
  Resource Version:  12983
  Self Link:         /apis/snapshot.storage.k8s.io/v1/namespaces/vault/volumesnapshots/velero-data-vault-0-q6ckf
  UID:               5660caf3-c063-423f-a84d-646ec1b8329a
Spec:
  Source:
    Persistent Volume Claim Name:  data-vault-0
  Volume Snapshot Class Name:      csi-ebs-snapclass
Status:
  Bound Volume Snapshot Content Name:  snapcontent-5660caf3-c063-423f-a84d-646ec1b8329a
  Creation Time:                       2020-12-26T05:13:50Z
  Ready To Use:                        false
  Restore Size:                        1Gi
Events:                                <none>
```

Get the `VolumeSnapshotContent`:

```bash
kubectl get volumesnapshotcontent
```

Output:

```text
NAME                                               READYTOUSE   RESTORESIZE   DELETIONPOLICY   DRIVER            VOLUMESNAPSHOTCLASS   VOLUMESNAPSHOT              AGE
snapcontent-b41f5b3d-9504-4c71-8ec0-f98b76743c6c   true         1073741824    Retain           ebs.csi.aws.com   csi-ebs-snapclass     velero-data-vault-0-jvjgj   9m21s
velero-velero-data-vault-0-jvjgj-bt44f             true         1073741824    Retain           ebs.csi.aws.com   csi-ebs-snapclass     velero-data-vault-0-jvjgj   4m4s
```

```bash
kubectl describe volumesnapshotcontent velero-velero-data-vault-0-jvjgj-bt44f
```

Output:

```text
Name:         velero-velero-data-vault-0-jvjgj-bt44f
Namespace:
Labels:       velero.io/restore-name=restore1
Annotations:  <none>
API Version:  snapshot.storage.k8s.io/v1
Kind:         VolumeSnapshotContent
Metadata:
  Creation Timestamp:  2020-12-26T05:53:37Z
  Finalizers:
    snapshot.storage.kubernetes.io/volumesnapshotcontent-bound-protection
  Generate Name:  velero-velero-data-vault-0-jvjgj-
  Generation:     2
  Managed Fields:
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:finalizers:
          .:
          v:"snapshot.storage.kubernetes.io/volumesnapshotcontent-bound-protection":
      f:spec:
        f:volumeSnapshotClassName:
        f:volumeSnapshotRef:
          f:uid:
    Manager:      snapshot-controller
    Operation:    Update
    Time:         2020-12-26T05:53:37Z
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:generateName:
        f:labels:
          .:
          f:velero.io/restore-name:
      f:spec:
        .:
        f:deletionPolicy:
        f:driver:
        f:source:
          .:
          f:snapshotHandle:
        f:volumeSnapshotRef:
          .:
          f:kind:
          f:name:
          f:namespace:
    Manager:      velero-plugin-for-csi
    Operation:    Update
    Time:         2020-12-26T05:53:37Z
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:status:
        .:
        f:creationTime:
        f:readyToUse:
        f:restoreSize:
        f:snapshotHandle:
    Manager:         csi-snapshotter
    Operation:       Update
    Time:            2020-12-26T05:53:39Z
  Resource Version:  26893
  Self Link:         /apis/snapshot.storage.k8s.io/v1/volumesnapshotcontents/velero-velero-data-vault-0-jvjgj-bt44f
  UID:               fdf5c6e6-9bba-4482-89a7-67c107b0bb12
Spec:
  Deletion Policy:  Retain
  Driver:           ebs.csi.aws.com
  Source:
    Snapshot Handle:           snap-099667b009a9dd808
  Volume Snapshot Class Name:  csi-ebs-snapclass
  Volume Snapshot Ref:
    Kind:       VolumeSnapshot
    Name:       velero-data-vault-0-jvjgj
    Namespace:  vault
    UID:        ed14bc7a-0e1f-431a-b15a-a9b29a702304
Status:
  Creation Time:    1608961730938000000
  Ready To Use:     true
  Restore Size:     1073741824
  Snapshot Handle:  snap-099667b009a9dd808
Events:             <none>
```

Check the snapshots in AWS:

```bash
aws ec2 describe-snapshots --filter Name=tag:kubernetes.io/cluster/${CLUSTER_FQDN},Values=owned | jq
```

Output:

```json
{
  "Snapshots": [
    {
      "Description": "Created by AWS EBS CSI driver for volume vol-08c1c1943749444d6",
      "Encrypted": true,
      "KmsKeyId": "arn:aws:kms:eu-central-1:729560437327:key/a753d4d9-5006-4bea-8351-34092cd7b34e",
      "OwnerId": "729560437327",
      "Progress": "0%",
      "SnapshotId": "snap-062a339572ef37867",
      "StartTime": "2020-12-26T05:13:50.874000+00:00",
      "State": "pending",
      "VolumeId": "vol-08c1c1943749444d6",
      "VolumeSize": 1,
      "Tags": [
        {
          "Key": "kubernetes.io/cluster/k1.k8s.mylabs.dev",
          "Value": "owned"
        },
        {
          "Key": "CSIVolumeSnapshotName",
          "Value": "snapshot-5660caf3-c063-423f-a84d-646ec1b8329a"
        },
        {
          "Key": "Name",
          "Value": "k1.k8s.mylabs.dev-dynamic-snapshot-5660caf3-c063-423f-a84d-646ec1b8329a"
        }
      ]
    }
  ]
}
```

See the files in S3 bucket:

```bash
aws s3 ls --recursive s3://${CLUSTER_FQDN}/velero/
```

Output:

```text
2020-12-26 06:13:55        735 velero/backups/backup-vault/backup-vault-csi-volumesnapshotcontents.json.gz
2020-12-26 06:13:55        561 velero/backups/backup-vault/backup-vault-csi-volumesnapshots.json.gz
2020-12-26 06:13:54       5461 velero/backups/backup-vault/backup-vault-logs.gz
2020-12-26 06:13:55         29 velero/backups/backup-vault/backup-vault-podvolumebackups.json.gz
2020-12-26 06:13:55        784 velero/backups/backup-vault/backup-vault-resource-list.json.gz
2020-12-26 06:13:55         29 velero/backups/backup-vault/backup-vault-volumesnapshots.json.gz
2020-12-26 06:13:55     141682 velero/backups/backup-vault/backup-vault.tar.gz
2020-12-26 06:13:55       2165 velero/backups/backup-vault/velero-backup.json
```

## Delete + Restore

Check the `vault` namespace and it's objects:

```bash
kubectl get pods,deployments,services,ingress,secrets,pvc,statefulset,service,configmap -n vault
```

Output:

```text
NAME                                        READY   STATUS    RESTARTS   AGE
pod/vault-0                                 1/1     Running   0          12m
pod/vault-agent-injector-6fcf464c66-pvf5h   1/1     Running   0          12m

NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/vault-agent-injector   1/1     1            1           12m

NAME                               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
service/vault                      ClusterIP   10.100.91.97     <none>        8200/TCP,8201/TCP   12m
service/vault-agent-injector-svc   ClusterIP   10.100.206.168   <none>        443/TCP             12m
service/vault-internal             ClusterIP   None             <none>        8200/TCP,8201/TCP   12m

NAME                       CLASS    HOSTS                     ADDRESS                                                                      PORTS     AGE
ingress.extensions/vault   <none>   vault.k1.k8s.mylabs.dev   a43195e480d754fb2a4d01dd39fd9cd9-1909688809.eu-central-1.elb.amazonaws.com   80, 443   12m

NAME                                      TYPE                                  DATA   AGE
secret/default-token-6qgnt                kubernetes.io/service-account-token   3      13m
secret/eks-creds                          Opaque                                2      13m
secret/ingress-cert-staging               kubernetes.io/tls                     2      13m
secret/sh.helm.release.v1.vault.v1        helm.sh/release.v1                    1      12m
secret/vault-agent-injector-token-qzdvw   kubernetes.io/service-account-token   3      12m
secret/vault-token-vqnvc                  kubernetes.io/service-account-token   3      12m

NAME                                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/data-vault-0   Bound    pvc-7c56c4b4-197a-4d0c-b6a5-0d1899965f8e   1Gi        RWO            gp3            12m

NAME                     READY   AGE
statefulset.apps/vault   1/1     12m

NAME                     DATA   AGE
configmap/vault-config   1      12m
```

Remove `vault` namespace - simulate unfortunate deletion of namespace:

```bash
kubectl delete namespace vault
```

Restore namespace `vault:

```bash
velero restore create restore1 --from-backup backup-vault --include-namespaces vault --wait
```

Output:

```text
Restore request "restore1" submitted successfully.
Waiting for restore to complete. You may safely press ctrl-c to stop waiting - your restore will continue in the background.
..
Restore completed with status: Completed. You may check for more information using the commands `velero restore describe restore1` and `velero restore logs restore1`.
```

Get recovery list:

```bash
velero restore get
```

Output:

```text
NAME       BACKUP         STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
restore1   backup-vault   Completed   2020-12-26 06:53:36 +0100 CET   2020-12-26 06:53:43 +0100 CET   0        0          2020-12-26 06:53:36 +0100 CET   <none>
```

Get the details about recovery:

```bash
velero restore describe restore1
```

Output:

```text
Name:         restore1
Namespace:    velero
Labels:       <none>
Annotations:  <none>

Phase:  Completed

Started:    2020-12-26 06:53:36 +0100 CET
Completed:  2020-12-26 06:53:43 +0100 CET

Backup:  backup-vault

Namespaces:
  Included:  vault
  Excluded:  <none>

Resources:
  Included:        *
  Excluded:        nodes, events, events.events.k8s.io, backups.velero.io, restores.velero.io, resticrepositories.velero.io
  Cluster-scoped:  auto

Namespace mappings:  <none>

Label selector:  <none>

Restore PVs:  auto
```

Verify the restored vault status. You should see "Initialized: true" and
"Sealed: false":

```bash
kubectl exec -n vault vault-0 -- vault status
```

Output:

```text
Key                      Value
---                      -----
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  1.5.4
Cluster Name             vault-cluster-92171e6f
Cluster ID               d1f486a5-524b-5129-05b4-82a2e0cedc22
HA Enabled               false
```

Delete the backup

```bash
velero backup delete backup-vault --confirm
```

Output:

```text
Request to delete backup "backup-vault" submitted successfully.
The backup will be fully deleted after all associated data (disk snapshots, backup files, restores) are removed.
```
