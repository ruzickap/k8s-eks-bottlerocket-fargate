# Velero

Velero helps with backup/restore of Kubernetes objects.

Install `velero`
[helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
and modify the
[default values](https://github.com/vmware-tanzu/helm-charts/blob/main/charts/velero/values.yaml).

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install --version 2.20.0 --namespace velero --create-namespace --values - velero vmware-tanzu/velero << EOF
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
```

Output:

```text
Backup request "backup-vault" submitted successfully.
Waiting for backup to complete. You may safely press ctrl-c to stop waiting - your backup will continue in the background.
...........................................
Backup completed with status: Completed. You may check for more information using the commands `velero backup describe backup-vault` and `velero backup logs backup-vault`.
```

Check the backups:

```bash
velero get backups
```

Output:

```text
NAME           STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
backup-vault   Completed   0        0          2021-03-20 10:33:09 +0100 CET   23h       default            <none>
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
Annotations:  velero.io/source-cluster-k8s-gitversion=v1.19.6-eks-49a6c0
              velero.io/source-cluster-k8s-major-version=1
              velero.io/source-cluster-k8s-minor-version=19+

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

Started:    2021-03-20 10:33:09 +0100 CET
Completed:  2021-03-20 10:33:23 +0100 CET

Expiration:  2021-03-21 10:33:06 +0100 CET

Total items to be backed up:  59
Items backed up:              59

Resource List:
  apps/v1/ControllerRevision:
    - vault/vault-6d54d99b56
  apps/v1/Deployment:
    - vault/vault-agent-injector
  apps/v1/ReplicaSet:
    - vault/vault-agent-injector-784ccfc788
  apps/v1/StatefulSet:
    - vault/vault
  discovery.k8s.io/v1beta1/EndpointSlice:
    - vault/vault-agent-injector-svc-2b5kl
    - vault/vault-gh7ts
    - vault/vault-internal-45mz5
  extensions/v1beta1/Ingress:
    - vault/vault
  networking.k8s.io/v1/Ingress:
    - vault/vault
  rbac.authorization.k8s.io/v1/ClusterRole:
    - system:auth-delegator
    - vault-agent-injector-clusterrole
  rbac.authorization.k8s.io/v1/ClusterRoleBinding:
    - vault-agent-injector-binding
    - vault-server-binding
  snapshot.storage.k8s.io/v1/VolumeSnapshot:
    - vault/velero-data-vault-0-x6zwp
  snapshot.storage.k8s.io/v1/VolumeSnapshotClass:
    - csi-ebs-snapclass
  snapshot.storage.k8s.io/v1/VolumeSnapshotContent:
    - snapcontent-99d118b4-ff11-4a3b-b1cf-c641ce4c034c
  v1/ConfigMap:
    - vault/istio-ca-root-cert
    - vault/vault-config
  v1/Endpoints:
    - vault/vault
    - vault/vault-agent-injector-svc
    - vault/vault-internal
  v1/Event:
    - vault/data-vault-0.166e0274861902cc
    - vault/data-vault-0.166e0274869fa7a7
    - vault/data-vault-0.166e027603aacce4
    - vault/vault-0.166e027487a29c45
    - vault/vault-0.166e0276ff65125c
    - vault/vault-0.166e02776887a965
    - vault/vault-0.166e02792445aa40
    - vault/vault-0.166e027a6720e046
    - vault/vault-0.166e027a87c7a42d
    - vault/vault-0.166e027a9173a604
    - vault/vault-0.166e027bf4483027
    - vault/vault-agent-injector-784ccfc788-k85xz.166e02747bd75a11
    - vault/vault-agent-injector-784ccfc788-k85xz.166e0274e58bf95b
    - vault/vault-agent-injector-784ccfc788-k85xz.166e02756e166de8
    - vault/vault-agent-injector-784ccfc788-k85xz.166e027575408047
    - vault/vault-agent-injector-784ccfc788-k85xz.166e02757ae9dbce
    - vault/vault-agent-injector-784ccfc788.166e027478ea56cd
    - vault/vault-agent-injector.166e027475d90563
    - vault/vault.166e027482720f09
    - vault/vault.166e02748431e981
    - vault/vault.166e02748760c6a9
  v1/Namespace:
    - vault
  v1/PersistentVolume:
    - pvc-2b5d124b-2021-465a-89a7-7666e7e43c86
  v1/PersistentVolumeClaim:
    - vault/data-vault-0
  v1/Pod:
    - vault/vault-0
    - vault/vault-agent-injector-784ccfc788-k85xz
  v1/Secret:
    - vault/default-token-69vcg
    - vault/eks-creds
    - vault/ingress-cert-staging
    - vault/sh.helm.release.v1.vault.v1
    - vault/vault-agent-injector-token-xzl69
    - vault/vault-token-xqgmt
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
Snapshot Content Name: snapcontent-99d118b4-ff11-4a3b-b1cf-c641ce4c034c
  Storage Snapshot ID: snap-0203474147721b8f6
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
vault       velero-data-vault-0-x6zwp   false        data-vault-0                           1Gi           csi-ebs-snapclass   snapcontent-99d118b4-ff11-4a3b-b1cf-c641ce4c034c   36s            37s
```

Check the `VolumeSnapshot` details:

```bash
kubectl describe volumesnapshots -n vault
```

Output:

```text
Name:         velero-data-vault-0-x6zwp
Namespace:    vault
Labels:       velero.io/backup-name=backup-vault
Annotations:  <none>
API Version:  snapshot.storage.k8s.io/v1
Kind:         VolumeSnapshot
Metadata:
  Creation Timestamp:  2021-03-20T09:33:17Z
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
    Time:         2021-03-20T09:33:17Z
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
    Time:            2021-03-20T09:33:18Z
  Resource Version:  27052
  Self Link:         /apis/snapshot.storage.k8s.io/v1/namespaces/vault/volumesnapshots/velero-data-vault-0-x6zwp
  UID:               99d118b4-ff11-4a3b-b1cf-c641ce4c034c
Spec:
  Source:
    Persistent Volume Claim Name:  data-vault-0
  Volume Snapshot Class Name:      csi-ebs-snapclass
Status:
  Bound Volume Snapshot Content Name:  snapcontent-99d118b4-ff11-4a3b-b1cf-c641ce4c034c
  Creation Time:                       2021-03-20T09:33:18Z
  Ready To Use:                        false
  Restore Size:                        1Gi
Events:
  Type    Reason            Age   From                 Message
  ----    ------            ----  ----                 -------
  Normal  CreatingSnapshot  38s   snapshot-controller  Waiting for a snapshot vault/velero-data-vault-0-x6zwp to be created by the CSI driver.
```

Get the `VolumeSnapshotContent`:

```bash
kubectl get volumesnapshotcontent
```

Output:

```text

NAME                                               READYTOUSE   RESTORESIZE   DELETIONPOLICY   DRIVER            VOLUMESNAPSHOTCLASS   VOLUMESNAPSHOT              AGE
snapcontent-99d118b4-ff11-4a3b-b1cf-c641ce4c034c   false        1073741824    Retain           ebs.csi.aws.com   csi-ebs-snapclass     velero-data-vault-0-x6zwp   38s
```

```bash
kubectl describe volumesnapshotcontent "$(kubectl get volumesnapshotcontent -o jsonpath="{.items[*].metadata.name}")"
```

Output:

```text
Name:         snapcontent-99d118b4-ff11-4a3b-b1cf-c641ce4c034c
Namespace:
Labels:       velero.io/backup-name=backup-vault
Annotations:  <none>
API Version:  snapshot.storage.k8s.io/v1
Kind:         VolumeSnapshotContent
Metadata:
  Creation Timestamp:  2021-03-20T09:33:17Z
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
    Time:         2021-03-20T09:33:17Z
    API Version:  snapshot.storage.k8s.io/v1beta1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:labels:
          .:
          f:velero.io/backup-name:
    Manager:      velero-plugin-for-csi
    Operation:    Update
    Time:         2021-03-20T09:33:22Z
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
    Time:            2021-03-20T09:33:55Z
  Resource Version:  28138
  Self Link:         /apis/snapshot.storage.k8s.io/v1/volumesnapshotcontents/snapcontent-99d118b4-ff11-4a3b-b1cf-c641ce4c034c
  UID:               d67982e5-2f02-47cc-9375-98d80cadb0c2
Spec:
  Deletion Policy:  Retain
  Driver:           ebs.csi.aws.com
  Source:
    Volume Handle:             vol-011280587cf55688f
  Volume Snapshot Class Name:  csi-ebs-snapclass
  Volume Snapshot Ref:
    API Version:       snapshot.storage.k8s.io/v1beta1
    Kind:              VolumeSnapshot
    Name:              velero-data-vault-0-x6zwp
    Namespace:         vault
    Resource Version:  27025
    UID:               99d118b4-ff11-4a3b-b1cf-c641ce4c034c
Status:
  Creation Time:    1616232798000000000
  Ready To Use:     false
  Restore Size:     1073741824
  Snapshot Handle:  snap-0203474147721b8f6
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
      "Description": "Created by AWS EBS CSI driver for volume vol-011280587cf55688f",
      "Encrypted": true,
      "KmsKeyId": "arn:aws:kms:eu-central-1:729560437327:key/a753d4d9-5006-4bea-8351-34092cd7b34e",
      "OwnerId": "729560437327",
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
aws s3 ls --recursive s3://${CLUSTER_FQDN}/velero/
```

Output:

```text
2021-03-20 10:33:24        768 velero/backups/backup-vault/backup-vault-csi-volumesnapshotcontents.json.gz
2021-03-20 10:33:24        556 velero/backups/backup-vault/backup-vault-csi-volumesnapshots.json.gz
2021-03-20 10:33:24       5801 velero/backups/backup-vault/backup-vault-logs.gz
2021-03-20 10:33:24         29 velero/backups/backup-vault/backup-vault-podvolumebackups.json.gz
2021-03-20 10:33:24        800 velero/backups/backup-vault/backup-vault-resource-list.json.gz
2021-03-20 10:33:24         29 velero/backups/backup-vault/backup-vault-volumesnapshots.json.gz
2021-03-20 10:33:24     149445 velero/backups/backup-vault/backup-vault.tar.gz
2021-03-20 10:33:24       2165 velero/backups/backup-vault/velero-backup.json
```

## Delete + Restore Vault using CSI Volume Snapshotting

Check the `vault` namespace and it's objects:

```bash
kubectl get pods,deployments,services,ingress,secrets,pvc,statefulset,service,configmap -n vault
```

Output:

```text
Warning: extensions/v1beta1 Ingress is deprecated in v1.14+, unavailable in v1.22+; use networking.k8s.io/v1 Ingress
NAME                                        READY   STATUS    RESTARTS   AGE
pod/vault-0                                 1/1     Running   0          13m
pod/vault-agent-injector-784ccfc788-k85xz   1/1     Running   0          13m

NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/vault-agent-injector   1/1     1            1           13m

NAME                               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
service/vault                      ClusterIP   10.100.140.68   <none>        8200/TCP,8201/TCP   13m
service/vault-agent-injector-svc   ClusterIP   10.100.30.161   <none>        443/TCP             13m
service/vault-internal             ClusterIP   None            <none>        8200/TCP,8201/TCP   13m

NAME                       CLASS    HOSTS                        ADDRESS                                                                            PORTS     AGE
ingress.extensions/vault   <none>   vault.kube1.k8s.mylabs.dev   ab0c678cc1ffd4c509d56b4ea3a81445-4dbb62ea4eb63a29.elb.eu-central-1.amazonaws.com   80, 443   13m

NAME                                      TYPE                                  DATA   AGE
secret/default-token-69vcg                kubernetes.io/service-account-token   3      13m
secret/eks-creds                          Opaque                                2      13m
secret/ingress-cert-staging               kubernetes.io/tls                     2      13m
secret/sh.helm.release.v1.vault.v1        helm.sh/release.v1                    1      13m
secret/vault-agent-injector-token-xzl69   kubernetes.io/service-account-token   3      13m
secret/vault-token-xqgmt                  kubernetes.io/service-account-token   3      13m

NAME                                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/data-vault-0   Bound    pvc-2b5d124b-2021-465a-89a7-7666e7e43c86   1Gi        RWO            gp3            13m

NAME                     READY   AGE
statefulset.apps/vault   1/1     13m

NAME                           DATA   AGE
configmap/istio-ca-root-cert   1      13m
configmap/vault-config         1      13m
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
..
Restore completed with status: Completed. You may check for more information using the commands `velero restore describe restore-vault` and `velero restore logs restore-vault`.
```

Get recovery list:

```bash
velero restore get
```

Output:

```text
NAME            BACKUP         STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
restore-vault   backup-vault   Completed   2021-03-20 10:34:16 +0100 CET   2021-03-20 10:34:19 +0100 CET   0        0          2021-03-20 10:34:16 +0100 CET   <none>
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

Phase:  Completed

Started:    2021-03-20 10:34:16 +0100 CET
Completed:  2021-03-20 10:34:19 +0100 CET

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
Version                  1.6.2
Storage Type             file
Cluster Name             vault-cluster-d47612b2
Cluster ID               31361e70-950f-39e0-532d-c3686b4550fb
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

```bash
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
  storageClassName: efs-dynamic-sc
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
    image: alpine
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

```bash
kubectl exec -it -n backup-test test-app -- cat /data/out.txt
```

Output:

```text
```

Run backup of "backup-test" namespace:

```bash
velero backup create backup-test --default-volumes-to-restic --ttl 24h --include-namespaces=backup-test --wait
```

Output:

```text
```

Check the backups:

```bash
velero get backups
```

Output:

```text
```

See the details of the "backup-test":

```bash
velero backup describe backup-test --details
```

Output:

```text
```

See the files in S3 bucket:

```bash
aws s3 ls --recursive s3://${CLUSTER_FQDN}/velero/backups/backup-test/
```

Output:

```text
```

Check the "backup-test" namespace and it's objects:

```bash
kubectl get pods,pvc,secret -n backup-test
```

Output:

```text
```

Remove "backup-test" namespace - simulate unfortunate deletion of namespace:

```bash
kubectl delete namespace backup-test
```

Restore the object in the "backup-test" namespace:

```bash
velero restore create restore-backup-test --from-backup backup-test --include-namespaces backup-test --wait
kubectl wait --namespace backup-test --for=condition=Ready --timeout=5m pod test-app
```

Output:

```text
```

Get recovery list:

```bash
velero restore get
```

Output:

```text
```

Get the details about recovery:

```bash
velero restore describe restore-backup-test
```

Output:

```text
```

Check the "backup-test" namespace and it's objects:

```bash
kubectl get pods,pvc,secret -n backup-test
```

Output:

```text
```

Check if the file "/data/out.txt" is being updated and see the "time gap":

```bash
kubectl exec -it -n backup-test test-app -- cat /data/out.txt
```

Output:

```text
```

Delete the backup

```bash
velero backup delete backup-test --confirm
```

Output:

```text
```

Delete namespace:

```bash
kubectl delete namespace backup-test
```
