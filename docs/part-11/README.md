# Velero

Velero helps with backup/restore of Kubernetes objects.

Install `velero`
[helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
and modify the
[default values](https://github.com/vmware-tanzu/helm-charts/blob/main/charts/velero/values.yaml).

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install --version 2.14.5 --namespace velero --create-namespace --values - velero vmware-tanzu/velero << EOF
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
.........................................
Backup completed with status: Completed. You may check for more information using the commands `velero backup describe backup-vault` and `velero backup logs backup-vault`.
```

Check the backups:

```bash
velero get backups
```

Output:

```text
NAME           STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
backup-vault   Completed   0        0          2020-12-27 17:38:03 +0100 CET   23h       default            <none>
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

Started:    2020-12-27 17:38:03 +0100 CET
Completed:  2020-12-27 17:38:13 +0100 CET

Expiration:  2020-12-28 17:38:01 +0100 CET

Total items to be backed up:  59
Items backed up:              59

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
    - vault/vault-agent-injector-svc-7s6ns
    - vault/vault-internal-5hjdx
    - vault/vault-wppbm
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
    - vault/velero-data-vault-0-tm9k5
  snapshot.storage.k8s.io/v1/VolumeSnapshotClass:
    - csi-ebs-snapclass
  snapshot.storage.k8s.io/v1/VolumeSnapshotContent:
    - snapcontent-f2151e39-5489-4f10-994d-d8dbaf7ecb68
  v1/ConfigMap:
    - vault/vault-config
  v1/Endpoints:
    - vault/vault
    - vault/vault-agent-injector-svc
    - vault/vault-internal
  v1/Event:
    - vault/data-vault-0.16549f78ea5a2152
    - vault/data-vault-0.16549f78ee61f5bb
    - vault/data-vault-0.16549f7b246cadc9
    - vault/vault-0.16549f78ec5d8eeb
    - vault/vault-0.16549f7c2fcc5b75
    - vault/vault-0.16549f7ca05b4bd5
    - vault/vault-0.16549f7e57548d80
    - vault/vault-0.16549f7f6dee94d4
    - vault/vault-0.16549f7f7eb687b0
    - vault/vault-0.16549f7f888743b8
    - vault/vault-0.16549f819311bf4d
    - vault/vault-0.16549f90b3cc940e
    - vault/vault-agent-injector-6fcf464c66-2khdj.16549f78e767c00f
    - vault/vault-agent-injector-6fcf464c66-2khdj.16549f79f461a234
    - vault/vault-agent-injector-6fcf464c66-2khdj.16549f7b3619f356
    - vault/vault-agent-injector-6fcf464c66-2khdj.16549f7b3d5d24c8
    - vault/vault-agent-injector-6fcf464c66-2khdj.16549f7b46073340
    - vault/vault-agent-injector-6fcf464c66.16549f78e5c7c766
    - vault/vault-agent-injector.16549f78e3955aa0
    - vault/vault.16549f78e939ec93
    - vault/vault.16549f78eb56713a
    - vault/vault.16549f78f2964d4b
  v1/Namespace:
    - vault
  v1/PersistentVolume:
    - pvc-46b6efdb-bc49-4301-b5df-bfddaabfb72d
  v1/PersistentVolumeClaim:
    - vault/data-vault-0
  v1/Pod:
    - vault/vault-0
    - vault/vault-agent-injector-6fcf464c66-2khdj
  v1/Secret:
    - vault/default-token-pbj86
    - vault/eks-creds
    - vault/ingress-cert-staging
    - vault/sh.helm.release.v1.vault.v1
    - vault/vault-agent-injector-token-9zhj2
    - vault/vault-token-f2qgf
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
Snapshot Content Name: snapcontent-f2151e39-5489-4f10-994d-d8dbaf7ecb68
  Storage Snapshot ID: snap-09e58a693894f86ed
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
vault       velero-data-vault-0-tm9k5   false        data-vault-0                           1Gi           csi-ebs-snapclass   snapcontent-f2151e39-5489-4f10-994d-d8dbaf7ecb68   5s             7s
```

Check the `VolumeSnapshot` details:

```bash
kubectl describe volumesnapshots -n vault
```

Output:

```text
Name:         velero-data-vault-0-tm9k5
Namespace:    vault
Labels:       velero.io/backup-name=backup-vault
Annotations:  <none>
API Version:  snapshot.storage.k8s.io/v1
Kind:         VolumeSnapshot
Metadata:
  Creation Timestamp:  2020-12-27T16:38:08Z
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
    Time:         2020-12-27T16:38:08Z
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
    Time:            2020-12-27T16:38:10Z
  Resource Version:  12577
  Self Link:         /apis/snapshot.storage.k8s.io/v1/namespaces/vault/volumesnapshots/velero-data-vault-0-tm9k5
  UID:               f2151e39-5489-4f10-994d-d8dbaf7ecb68
Spec:
  Source:
    Persistent Volume Claim Name:  data-vault-0
  Volume Snapshot Class Name:      csi-ebs-snapclass
Status:
  Bound Volume Snapshot Content Name:  snapcontent-f2151e39-5489-4f10-994d-d8dbaf7ecb68
  Creation Time:                       2020-12-27T16:38:10Z
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
snapcontent-f2151e39-5489-4f10-994d-d8dbaf7ecb68   false        1073741824    Retain           ebs.csi.aws.com   csi-ebs-snapclass     velero-data-vault-0-tm9k5   8s
```

```bash
kubectl describe volumesnapshotcontent "$(kubectl get volumesnapshotcontent -o jsonpath="{.items[*].metadata.name}")"
```

Output:

```text
Name:         snapcontent-f2151e39-5489-4f10-994d-d8dbaf7ecb68
Namespace:
Labels:       velero.io/backup-name=backup-vault
Annotations:  <none>
API Version:  snapshot.storage.k8s.io/v1
Kind:         VolumeSnapshotContent
Metadata:
  Creation Timestamp:  2020-12-27T16:38:08Z
  Finalizers:
    snapshot.storage.kubernetes.io/volumesnapshotcontent-bound-protection
  Generation:  1
  Managed Fields:
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:finalizers:
          .:
          v:"snapshot.storage.kubernetes.io/volumesnapshotcontent-bound-protection":
      f:spec:
        .:
        f:deletionPolicy:
        f:driver:
        f:source:
          .:
          f:volumeHandle:
        f:volumeSnapshotClassName:
        f:volumeSnapshotRef:
          .:
          f:apiVersion:
          f:kind:
          f:name:
          f:namespace:
          f:resourceVersion:
          f:uid:
    Manager:      snapshot-controller
    Operation:    Update
    Time:         2020-12-27T16:38:08Z
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:status:
        .:
        f:creationTime:
        f:readyToUse:
        f:restoreSize:
        f:snapshotHandle:
    Manager:      csi-snapshotter
    Operation:    Update
    Time:         2020-12-27T16:38:13Z
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:labels:
          .:
          f:velero.io/backup-name:
    Manager:         velero-plugin-for-csi
    Operation:       Update
    Time:            2020-12-27T16:38:13Z
  Resource Version:  12596
  Self Link:         /apis/snapshot.storage.k8s.io/v1/volumesnapshotcontents/snapcontent-f2151e39-5489-4f10-994d-d8dbaf7ecb68
  UID:               af8659b9-5600-43b0-948b-691ed12a8b19
Spec:
  Deletion Policy:  Retain
  Driver:           ebs.csi.aws.com
  Source:
    Volume Handle:             vol-0cf0418c9165d8ada
  Volume Snapshot Class Name:  csi-ebs-snapclass
  Volume Snapshot Ref:
    API Version:       snapshot.storage.k8s.io/v1beta1
    Kind:              VolumeSnapshot
    Name:              velero-data-vault-0-tm9k5
    Namespace:         vault
    Resource Version:  12556
    UID:               f2151e39-5489-4f10-994d-d8dbaf7ecb68
Status:
  Creation Time:    1609087090000000000
  Ready To Use:     false
  Restore Size:     1073741824
  Snapshot Handle:  snap-09e58a693894f86ed
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
      "Description": "Created by AWS EBS CSI driver for volume vol-0cf0418c9165d8ada",
      "Encrypted": true,
      "KmsKeyId": "arn:aws:kms:eu-central-1:729560437327:key/a753d4d9-5006-4bea-8351-34092cd7b34e",
      "OwnerId": "729560437327",
      "Progress": "100%",
      "SnapshotId": "snap-09e58a693894f86ed",
      "StartTime": "2020-12-27T16:38:10.172000+00:00",
      "State": "completed",
      "VolumeId": "vol-0cf0418c9165d8ada",
      "VolumeSize": 1,
      "Tags": [
        {
          "Key": "kubernetes.io/cluster/k1.k8s.mylabs.dev",
          "Value": "owned"
        },
        {
          "Key": "CSIVolumeSnapshotName",
          "Value": "snapshot-f2151e39-5489-4f10-994d-d8dbaf7ecb68"
        },
        {
          "Key": "Name",
          "Value": "k1.k8s.mylabs.dev-dynamic-snapshot-f2151e39-5489-4f10-994d-d8dbaf7ecb68"
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
2020-12-27 17:38:15        734 velero/backups/backup-vault/backup-vault-csi-volumesnapshotcontents.json.gz
2020-12-27 17:38:15        557 velero/backups/backup-vault/backup-vault-csi-volumesnapshots.json.gz
2020-12-27 17:38:14       5376 velero/backups/backup-vault/backup-vault-logs.gz
2020-12-27 17:38:15         29 velero/backups/backup-vault/backup-vault-podvolumebackups.json.gz
2020-12-27 17:38:15        799 velero/backups/backup-vault/backup-vault-resource-list.json.gz
2020-12-27 17:38:15         29 velero/backups/backup-vault/backup-vault-volumesnapshots.json.gz
2020-12-27 17:38:14     141673 velero/backups/backup-vault/backup-vault.tar.gz
2020-12-27 17:38:14       2165 velero/backups/backup-vault/velero-backup.json
```

## Delete + Restore

Check the `vault` namespace and it's objects:

```bash
kubectl get pods,deployments,services,ingress,secrets,pvc,statefulset,service,configmap -n vault
```

Output:

```text
NAME                                        READY   STATUS    RESTARTS   AGE
pod/vault-0                                 1/1     Running   0          13m
pod/vault-agent-injector-6fcf464c66-2khdj   1/1     Running   0          13m

NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/vault-agent-injector   1/1     1            1           13m

NAME                               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
service/vault                      ClusterIP   10.100.111.134   <none>        8200/TCP,8201/TCP   13m
service/vault-agent-injector-svc   ClusterIP   10.100.101.131   <none>        443/TCP             13m
service/vault-internal             ClusterIP   None             <none>        8200/TCP,8201/TCP   13m

NAME                       CLASS    HOSTS                     ADDRESS                                                                     PORTS     AGE
ingress.extensions/vault   <none>   vault.k1.k8s.mylabs.dev   a611d90b2228e45daaf92b7e6e6de94d-104394448.eu-central-1.elb.amazonaws.com   80, 443   13m

NAME                                      TYPE                                  DATA   AGE
secret/default-token-pbj86                kubernetes.io/service-account-token   3      13m
secret/eks-creds                          Opaque                                2      13m
secret/ingress-cert-staging               kubernetes.io/tls                     2      13m
secret/sh.helm.release.v1.vault.v1        helm.sh/release.v1                    1      13m
secret/vault-agent-injector-token-9zhj2   kubernetes.io/service-account-token   3      13m
secret/vault-token-f2qgf                  kubernetes.io/service-account-token   3      13m

NAME                                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/data-vault-0   Bound    pvc-46b6efdb-bc49-4301-b5df-bfddaabfb72d   1Gi        RWO            gp3            13m

NAME                     READY   AGE
statefulset.apps/vault   1/1     13m

NAME                     DATA   AGE
configmap/vault-config   1      13m
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
restore1   backup-vault   Completed   2020-12-27 17:38:46 +0100 CET   2020-12-27 17:38:48 +0100 CET   0        0          2020-12-27 17:38:46 +0100 CET   <none>
```

Get the details about recovery:

```bash
velero restore describe restore1
sleep 60
```

Output:

```text
Name:         restore1
Namespace:    velero
Labels:       <none>
Annotations:  <none>

Phase:  Completed

Started:    2020-12-27 17:38:46 +0100 CET
Completed:  2020-12-27 17:38:48 +0100 CET

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
Cluster Name             vault-cluster-108b6091
Cluster ID               4968dab5-e687-fd3d-6ee7-c03ce448e7f6
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
