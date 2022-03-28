# Velero

Velero helps with backup/restore of Kubernetes objects.

Install `velero`
[helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
and modify the
[default values](https://github.com/vmware-tanzu/helm-charts/blob/main/charts/velero/values.yaml).

```bash
helm repo add --force-update vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm upgrade --install --version 2.23.5 --namespace velero --create-namespace --values - velero vmware-tanzu/velero << EOF
initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.2.0
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
serviceAccount:
  server:
    create: false
    name: velero
credentials:
  useSecret: false
deployRestic: true
EOF
```

## Backup Vault using CSI Volume Snapshotting

This example showing Velero backup using snapshots `features: EnableCSI`:

Run backup of `vault` namespace:

```bash
velero backup create backup-vault --ttl 24h --include-namespaces=vault --wait
sleep 10
```

Output:

```text
Backup request "backup-vault" submitted successfully.
Waiting for backup to complete. You may safely press ctrl-c to stop waiting - your backup will continue in the background.
.............................
Backup completed with status: Completed. You may check for more information using the commands `velero backup describe backup-vault` and `velero backup logs backup-vault`.
```

Check the backups:

```bash
velero get backups
```

Output:

```text
NAME           STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
backup-vault   Completed   0        0          2021-11-29 19:35:48 +0100 CET   23h       default            <none>
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
Annotations:  velero.io/source-cluster-k8s-gitversion=v1.21.2-eks-06eac09
              velero.io/source-cluster-k8s-major-version=1
              velero.io/source-cluster-k8s-minor-version=21+

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

Started:    2021-11-29 19:35:48 +0100 CET
Completed:  2021-11-29 19:36:13 +0100 CET

Expiration:  2021-11-30 19:35:47 +0100 CET

Total items to be backed up:  50
Items backed up:              50

Resource List:
  apiextensions.k8s.io/v1/CustomResourceDefinition:
    - apps.catalog.cattle.io
    - policyreports.wgpolicyk8s.io
  apps/v1/ControllerRevision:
    - vault/vault-5d64bdf4c
  apps/v1/StatefulSet:
    - vault/vault
  catalog.cattle.io/v1/App:
    - vault/vault
  discovery.k8s.io/v1/EndpointSlice:
    - vault/vault-internal-jmw6b
    - vault/vault-k4bsj
  extensions/v1beta1/Ingress:
    - vault/vault
  networking.k8s.io/v1/Ingress:
    - vault/vault
  rbac.authorization.k8s.io/v1/ClusterRole:
    - system:auth-delegator
  rbac.authorization.k8s.io/v1/ClusterRoleBinding:
    - vault-server-binding
  snapshot.storage.k8s.io/v1/VolumeSnapshot:
    - vault/velero-data-vault-0-tjzmn
  snapshot.storage.k8s.io/v1/VolumeSnapshotClass:
    - csi-ebs-snapclass
  snapshot.storage.k8s.io/v1/VolumeSnapshotContent:
    - snapcontent-4590ab05-9985-46d1-b933-9ac6cbf8f273
  v1/ConfigMap:
    - vault/istio-ca-root-cert
    - vault/kube-root-ca.crt
    - vault/vault-config
  v1/Endpoints:
    - vault/vault
    - vault/vault-internal
  v1/Event:
    - vault/data-vault-0.16bc16518e27caa7
    - vault/data-vault-0.16bc1651a2cec15e
    - vault/data-vault-0.16bc1651a472319d
    - vault/data-vault-0.16bc165276a2e75e
    - vault/vault-0.16bc16528ff1897e
    - vault/vault-0.16bc1653507ef368
    - vault/vault-0.16bc1655a8f8ba2c
    - vault/vault-0.16bc1657c6ec0ccf
    - vault/vault-0.16bc1657d8e90a9b
    - vault/vault-0.16bc1657e8e0c068
    - vault/vault-0.16bc16599ccee60e
    - vault/vault.16bc16517c637f61
    - vault/vault.16bc16518e5caae2
    - vault/vault.16bc16519b84095f
    - vault/vault.16bc16519cec3f09
    - vault/vault.16bc16677d87006d
    - vault/vault.16bc181570c799e4
    - vault/vault.16bc1825c7e610bc
  v1/Namespace:
    - vault
  v1/PersistentVolume:
    - pvc-7c542be7-2c63-4c44-9634-19ac2f1b291c
  v1/PersistentVolumeClaim:
    - vault/data-vault-0
  v1/Pod:
    - vault/vault-0
  v1/Secret:
    - vault/default-token-vbfds
    - vault/ingress-cert-staging
    - vault/sh.helm.release.v1.vault.v1
    - vault/vault-token-v7px6
  v1/Service:
    - vault/vault
    - vault/vault-internal
  v1/ServiceAccount:
    - vault/default
    - vault/vault
  wgpolicyk8s.io/v1alpha1/PolicyReport:
    - vault/polr-ns-vault

Velero-Native Snapshots: <none included>

CSI Volume Snapshots:
Snapshot Content Name: snapcontent-4590ab05-9985-46d1-b933-9ac6cbf8f273
  Storage Snapshot ID: snap-00bbc8da2281aeac8
  Snapshot Size (bytes): 1073741824
  Ready to use: true
```

List all the `VolumeSnapshot` objects:

```bash
kubectl get volumesnapshots --all-namespaces
```

Output:

```text
NAMESPACE   NAME                        READYTOUSE   SOURCEPVC      SOURCESNAPSHOTCONTENT   RESTORESIZE   SNAPSHOTCLASS       SNAPSHOTCONTENT                                    CREATIONTIME   AGE
vault       velero-data-vault-0-tjzmn   true         data-vault-0                           1Gi           csi-ebs-snapclass   snapcontent-4590ab05-9985-46d1-b933-9ac6cbf8f273   9s             10s
```

Check the `VolumeSnapshot` details:

```bash
kubectl describe volumesnapshots -n vault
```

Output:

```text
Name:         velero-data-vault-0-tjzmn
Namespace:    vault
Labels:       velero.io/backup-name=backup-vault
Annotations:  <none>
API Version:  snapshot.storage.k8s.io/v1
Kind:         VolumeSnapshot
Metadata:
  Creation Timestamp:  2021-11-29T18:36:08Z
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
    Time:         2021-11-29T18:36:08Z
    API Version:  snapshot.storage.k8s.io/v1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:finalizers:
          .:
          v:"snapshot.storage.kubernetes.io/volumesnapshot-as-source-protection":
      f:status:
        .:
        f:boundVolumeSnapshotContentName:
        f:creationTime:
        f:readyToUse:
        f:restoreSize:
    Manager:         snapshot-controller
    Operation:       Update
    Time:            2021-11-29T18:36:09Z
  Resource Version:  58212
  UID:               4590ab05-9985-46d1-b933-9ac6cbf8f273
Spec:
  Source:
    Persistent Volume Claim Name:  data-vault-0
  Volume Snapshot Class Name:      csi-ebs-snapclass
Status:
  Bound Volume Snapshot Content Name:  snapcontent-4590ab05-9985-46d1-b933-9ac6cbf8f273
  Creation Time:                       2021-11-29T18:36:09Z
  Ready To Use:                        true
  Restore Size:                        1Gi
Events:
  Type    Reason            Age   From                 Message
  ----    ------            ----  ----                 -------
  Normal  CreatingSnapshot  11s   snapshot-controller  Waiting for a snapshot vault/velero-data-vault-0-tjzmn to be created by the CSI driver.
  Normal  SnapshotCreated   10s   snapshot-controller  Snapshot vault/velero-data-vault-0-tjzmn was successfully created by the CSI driver.
  Normal  SnapshotReady     5s    snapshot-controller  Snapshot vault/velero-data-vault-0-tjzmn is ready to use.
```

Get the `VolumeSnapshotContent`:

```bash
kubectl get volumesnapshotcontent
```

Output:

```text
NAME                                               READYTOUSE   RESTORESIZE   DELETIONPOLICY   DRIVER            VOLUMESNAPSHOTCLASS   VOLUMESNAPSHOT              VOLUMESNAPSHOTNAMESPACE   AGE
snapcontent-4590ab05-9985-46d1-b933-9ac6cbf8f273   true         1073741824    Retain           ebs.csi.aws.com   csi-ebs-snapclass     velero-data-vault-0-tjzmn   vault                     12s
```

```bash
kubectl describe volumesnapshotcontent "$(kubectl get volumesnapshotcontent -o jsonpath="{.items[*].metadata.name}")"
```

Output:

```text
Name:         snapcontent-4590ab05-9985-46d1-b933-9ac6cbf8f273
Namespace:
Labels:       velero.io/backup-name=backup-vault
Annotations:  <none>
API Version:  snapshot.storage.k8s.io/v1
Kind:         VolumeSnapshotContent
Metadata:
  Creation Timestamp:  2021-11-29T18:36:08Z
  Finalizers:
    snapshot.storage.kubernetes.io/volumesnapshotcontent-bound-protection
  Generation:  1
  Managed Fields:
    API Version:  snapshot.storage.k8s.io/v1
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
    Time:         2021-11-29T18:36:08Z
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
    Time:         2021-11-29T18:36:12Z
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:labels:
          .:
          f:velero.io/backup-name:
    Manager:         velero-plugin-for-csi
    Operation:       Update
    Time:            2021-11-29T18:36:13Z
  Resource Version:  58204
  UID:               ac2e744b-a973-43f7-94f2-0a19e96fbded
Spec:
  Deletion Policy:  Retain
  Driver:           ebs.csi.aws.com
  Source:
    Volume Handle:             vol-02eaf309a1814296b
  Volume Snapshot Class Name:  csi-ebs-snapclass
  Volume Snapshot Ref:
    API Version:       snapshot.storage.k8s.io/v1
    Kind:              VolumeSnapshot
    Name:              velero-data-vault-0-tjzmn
    Namespace:         vault
    Resource Version:  58099
    UID:               4590ab05-9985-46d1-b933-9ac6cbf8f273
Status:
  Creation Time:    1638210969214000000
  Ready To Use:     true
  Restore Size:     1073741824
  Snapshot Handle:  snap-00bbc8da2281aeac8
Events:             <none>
```

Check the snapshots in AWS:

```bash
aws ec2 describe-snapshots --filter "Name=tag:kubernetes.io/cluster/${CLUSTER_FQDN},Values=owned" | jq
```

Output:

```json
{
  "Snapshots": [
    {
      "Description": "Created by AWS EBS CSI driver for volume vol-011280587cf55688f",
      "Encrypted": true,
      "KmsKeyId": "arn:aws:kms:eu-central-1:7xxxxxxxxxx7:key/a753d4d9-5006-4bea-8351-34092cd7b34e",
      "OwnerId": "7xxxxxxxxxx7",
      "Progress": "99%",
      "SnapshotId": "snap-0203474147721b8f6",
      "StartTime": "2021-03-20T09:33:18.023000+00:00",
      "State": "pending",
      "VolumeId": "vol-011280587cf55688f",
      "VolumeSize": 1,
      "Tags": [
        {
          "Key": "CSIVolumeSnapshotName",
          "Value": "snapshot-99d118b4-ff11-4a3b-b1cf-c641ce4c034c"
        },
        {
          "Key": "kubernetes.io/cluster/kube1.k8s.mylabs.dev",
          "Value": "owned"
        },
        {
          "Key": "Name",
          "Value": "kube1.k8s.mylabs.dev-dynamic-snapshot-99d118b4-ff11-4a3b-b1cf-c641ce4c034c"
        }
      ]
    }
  ]
}
```

See the files in S3 bucket:

```bash
aws s3 ls --recursive "s3://${CLUSTER_FQDN}/velero/"
```

Output:

```text
2021-11-29 19:36:14        740 velero/backups/backup-vault/backup-vault-csi-volumesnapshotcontents.json.gz
2021-11-29 19:36:14        539 velero/backups/backup-vault/backup-vault-csi-volumesnapshots.json.gz
2021-11-29 19:36:14       8189 velero/backups/backup-vault/backup-vault-logs.gz
2021-11-29 19:36:14         29 velero/backups/backup-vault/backup-vault-podvolumebackups.json.gz
2021-11-29 19:36:14        772 velero/backups/backup-vault/backup-vault-resource-list.json.gz
2021-11-29 19:36:14         29 velero/backups/backup-vault/backup-vault-volumesnapshots.json.gz
2021-11-29 19:36:14     180977 velero/backups/backup-vault/backup-vault.tar.gz
2021-11-29 19:36:14       2089 velero/backups/backup-vault/velero-backup.json
```

## Delete + Restore Vault using CSI Volume Snapshotting

Check the `vault` namespace and it's objects:

```bash
kubectl get pods,deployments,services,ingress,secrets,pvc,statefulset,service,configmap -n vault
```

Output:

```text
NAME          READY   STATUS    RESTARTS   AGE
pod/vault-0   1/1     Running   0          34m

NAME                     TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
service/vault            ClusterIP   10.100.171.190   <none>        8200/TCP,8201/TCP   34m
service/vault-internal   ClusterIP   None             <none>        8200/TCP,8201/TCP   34m

NAME                              CLASS    HOSTS                        ADDRESS                                                                         PORTS     AGE
ingress.networking.k8s.io/vault   <none>   vault.kube1.k8s.mylabs.dev   a3eb1591c3e6146ef99ccb15b1f35f50-fb80a50b84de3021.elb.eu-west-1.amazonaws.com   80, 443   34m

NAME                                 TYPE                                  DATA   AGE
secret/default-token-vbfds           kubernetes.io/service-account-token   3      77m
secret/ingress-cert-staging          kubernetes.io/tls                     2      61m
secret/sh.helm.release.v1.vault.v1   helm.sh/release.v1                    1      34m
secret/vault-token-v7px6             kubernetes.io/service-account-token   3      77m

NAME                                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/data-vault-0   Bound    pvc-7c542be7-2c63-4c44-9634-19ac2f1b291c   1Gi        RWO            gp3            34m

NAME                     READY   AGE
statefulset.apps/vault   1/1     34m

NAME                           DATA   AGE
configmap/istio-ca-root-cert   1      58m
configmap/kube-root-ca.crt     1      77m
configmap/vault-config         1      34m
```

Remove `vault` namespace - simulate unfortunate deletion of namespace:

```bash
kubectl delete namespace vault
```

Restore namespace `vault:

```bash
velero restore create restore-vault --from-backup backup-vault --include-namespaces vault --wait
```

Output:

```text
Restore request "restore-vault" submitted successfully.
Waiting for restore to complete. You may safely press ctrl-c to stop waiting - your restore will continue in the background.
....
Restore completed with status: Completed. You may check for more information using the commands `velero restore describe restore-vault` and `velero restore logs restore-vault`.
```

Get recovery list:

```bash
velero restore get
```

Output:

```text
NAME            BACKUP         STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
restore-vault   backup-vault   Completed   2021-11-29 19:36:47 +0100 CET   2021-11-29 19:36:51 +0100 CET   0        1          2021-11-29 19:36:46 +0100 CET   <none>
```

Get the details about recovery:

```bash
velero restore describe restore-vault
kubectl wait --namespace vault --for=condition=Ready --timeout=5m pod vault-0
```

Output:

```text
Name:         restore-vault
Namespace:    velero
Labels:       <none>
Annotations:  <none>

Phase:                       Completed
Total items to be restored:  26
Items restored:              26

Started:    2021-11-29 19:36:47 +0100 CET
Completed:  2021-11-29 19:36:51 +0100 CET

Warnings:
  Velero:     <none>
  Cluster:    <none>
  Namespaces:
    vault:  could not restore, apps.catalog.cattle.io "vault" already exists. Warning: the in-cluster version is different than the backed-up version.

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

Preserve Service NodePorts:  auto
```

Verify the restored vault status. You should see "Initialized: true" and
"Sealed: false":

```bash
kubectl exec -n vault vault-0 -- vault status || true
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
Version                  1.8.1
Storage Type             file
Cluster Name             vault-cluster-35710bf5
Cluster ID               4b7168eb-6bfc-30fa-8ab9-060477394dc6
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

## Backup + Delete + Restore app with EFS storage using restic

Run pod writing to the EFS storage:

```shell
kubectl apply -f - << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: backup-test
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-backup-test-pv
  namespace: backup-test
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-drupal
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-app
  namespace: backup-test
spec:
  containers:
  - name: app
    image: alpine:3
    securityContext:
      runAsUser: 1000
      runAsGroup: 3000
      readOnlyRootFilesystem: true
    command: ["/bin/sh"]
    args: ["-c", "while true; do date >> /data/out.txt; sleep 5; done"]
    volumeMounts:
    - name: persistent-storage
      mountPath: /data
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
  volumes:
  - name: persistent-storage
    persistentVolumeClaim:
      claimName: efs-backup-test-pv
EOF
kubectl wait --namespace backup-test --for=condition=Ready --timeout=5m pod test-app
sleep 10
```

The file is being continuously updated

```shell
kubectl exec -it -n backup-test test-app -- cat /data/out.txt
```

Output:

```text
```

Run backup of "backup-test" namespace:

```shell
velero backup create backup-test --default-volumes-to-restic --ttl 24h --include-namespaces=backup-test --wait
```

Output:

```text
```

Check the backups:

```shell
velero get backups
```

Output:

```text
```

See the details of the "backup-test":

```shell
velero backup describe backup-test --details
```

Output:

```text
```

See the files in S3 bucket:

```shell
aws s3 ls --recursive "s3://${CLUSTER_FQDN}/velero/backups/backup-test/"
```

Output:

```text
```

Check the "backup-test" namespace and it's objects:

```shell
kubectl get pods,pvc,secret -n backup-test
```

Output:

```text
```

Remove "backup-test" namespace - simulate unfortunate deletion of namespace:

```shell
kubectl delete namespace backup-test
```

Restore the object in the "backup-test" namespace:

```shell
velero restore create restore-backup-test --from-backup backup-test --include-namespaces backup-test --wait
kubectl wait --namespace backup-test --for=condition=Ready --timeout=5m pod test-app
```

Output:

```text
```

Get recovery list:

```shell
velero restore get
```

Output:

```text
```

Get the details about recovery:

```shell
velero restore describe restore-backup-test
```

Output:

```text
```

Check the "backup-test" namespace and it's objects:

```shell
kubectl get pods,pvc,secret -n backup-test
```

Output:

```text
```

Check if the file "/data/out.txt" is being updated and see the "time gap":

```shell
kubectl exec -it -n backup-test test-app -- cat /data/out.txt
```

Output:

```text
```

Delete the backup

```shell
velero backup delete backup-test --confirm
```

Output:

```text
```

Delete namespace:

```shell
kubectl delete namespace backup-test
```
